#!/bin/bash

. /home/pi/.bashrc

########## Example config ##########

## put in a config file ##
#TAG="beta1"
#TAGFILE="$TAG.rev"
#TAGREV=$(cat $TAGFILE)

#PPA="ppa:wsnipex/xbmc-nightly"

#REPO_DIR="/data/packages/xbmc-mainline/xbmc"
#OUTPUT_DIR="/data/packages/xbmc-mainline"
#BUILD_REPO="master"
#UPSTREAM_REPO="xbmc-upstream"
#UPSTREAM_BRANCH="master"
#PVRADDONS_REPO_DIR="/data/packages/xbmc-mainline/xbmc-pvr-addons"
#PVR_REPO="pvr-addons-upstream"
#PVR_BRANCH="master"
#DEBIAN="/data/packages/xbmc-mainline/debian"
#LOG="$PWD/gitbuild.log"
#FORCE_BUILD="True"
#DISTS="quantal precise oneiric"
##DISTS="quantal"
#PATCHES=(path/to/patchfile path/to/another/patchfile)
########################################

function updateRepo {
    cd $REPO_DIR || exit 1
    git stash
    git checkout $BUILD_REPO >/dev/null 2>&1 || exit 2
    git fetch $UPSTREAM_REPO >/dev/null 2>&1 || exit 2
    createChangelog
    git reset --hard $UPSTREAM_REPO/$UPSTREAM_BRANCH >> $LOG || exit 2
    git clean -Xfd
    [[ -n $PATCHES ]] && addPatchesFromFile
}

function addPatchesFromFile {
    for patchfile in ${PATCHES[*]}
    do
        echo "adding patch: $patchfile" >> $LOG
        git apply $patchfile >> $LOG 2>&1
    done

}

function getGitRev {
    local branch=$1
    cd $REPO_DIR || exit 1
    #REV=$(git log --no-merges -1 --pretty=format:"%h %an %B" $branch)
    #REV=$(git log --no-merges -1 --pretty=format:"%h" $branch)
    REV=$(git log -1 --pretty=format:"%h" $branch)
    echo $REV # return
}

function compareRevs {
    local currev=$1
    local upstreamrev=$2
    [[ $currev != $upstreamrev ]] && echo "False" || echo "True"
}

function buildPackage {
    # check if build repo updated ok
    local newrev=$(getGitRev $BUILD_REPO)
    if [[ $(compareRevs $newrev $UPSTREAMREV) == "False" ]]
    then
        echo "local repo update error" >> $LOG
        exit 2
    fi
    echo "building new package with git rev $UPSTREAMREV" >> $LOG
    [[ -z $TAG ]] && TAG=$UPSTREAMREV
    [[ -z $TAGREV ]] && TAGREV=0
    archiveRepo
    cd $REPO_DIR/debian
    #sed -i "s/~git.*-0/${DEST#xbmc-12.0}-${TAGREV}/g" changelog.tmp
    sed -i "s/2:.*-0/2:${DEST#xbmc-}-${TAGREV}/g" changelog.tmp
    [[ $(createDebs) -eq 0 ]] && uploadpkgs && saveTagRev
}

function archiveRepo {
    [[ $INCLUDE_PVR != "False" ]] && updatePvrAddons

    cd $REPO_DIR || exit 1
    echo $UPSTREAMREV > gitrev
    echo $UPSTREAMREV > VERSION
    DEST="xbmc-${RELEASEV}~git$(date '+%Y%m%d.%H%M')-${TAG}"
    [[ -d debian ]] && rm -rf debian 
    cp -r $DEBIAN . #TODO better debian dir handling
    mv $(basename $DEBIAN) debian
    #git archive --format tar.gz -o ../${DEST}.tar.gz $BUILD_REPO >> $LOG 2>&1
    cd ..
    tar -czf ${DEST}.tar.gz -h --exclude .git $(basename $REPO_DIR)

    ln -s ${DEST}.tar.gz ${DEST/-/_}.orig.tar.gz
    echo "Output Archive: ${DEST}.tar.gz" >> $LOG
}

function updatePvrAddons {
    cd $PVRADDONS_REPO_DIR || exit 1
    echo "updating PVR Addons in $PVRADDONS_REPO_DIR" >> $LOG
    echo $PWD
    git clean -Xfd #>> $LOG
    git fetch $PVR_REPO >> $LOG 2>&1
    git reset --hard $PVR_REPO/$PVR_BRANCH >> $LOG 2>&1
    cd ..
    mkdir $REPO_DIR/pvr-addons
    cp -r $PVRADDONS_REPO_DIR/* $REPO_DIR/pvr-addons
    
}

function createDebs {
    cd $REPO_DIR
    for i in $DISTS
    do
        echo "building $i" >> $LOG
        sed "s/dist/$i/g" debian/changelog.tmp > debian/changelog
        debuild $BUILDOPT -S -k"wsnipex <wsnipex@a1.net>" >> $LOG 2>&1
        #BUILDOPT="-sd"
    done
    echo $?
}

function uploadpkgs {
    cd $REPO_DIR/..
    PKGS=$(ls ${DEST/-/_}*.changes)
    for pkg in ${PKGS[*]}
    do
        echo "uploading $pkg to $PPA" >> $LOG 2>&1
        dput $PPA $pkg >> $LOG
    done
    [ $? -eq 0 ] && mv ${DEST/-/_}* ${DEST}* $OUTPUT_DIR
}

function saveTagRev {
    echo "$TAGREV" > $TAGFILE
}

function createChangelog {
    #cd $REPO_DIR || exit 1
    local changes="/tmp/changes-tmp"
    local commits="/tmp/commits-tmp"
    local author
    local subject

    rm -f $changes $commits >/dev/null 2>&1
    git log --no-merges --pretty=format:"%an|%s"%n $UPSTREAM_REPO/$UPSTREAM_BRANCH --not $BUILD_REPO > $commits
    cat $commits | sed '/^$/d' | while read line
    do
    #echo $line
       echo >> $changes
       author=$(echo $line | awk -F '|' '{ print $1}')
       subject=$(echo $line | awk -F '|' '{ print $2}')
       echo '  ['$author']' >> $changes
       echo '   * '$subject >> $changes
    done
    echo >> $changes
    cp $DEBIAN/changelog.tmp $DEBIAN/changelog.tmp.old
    sed -i "/^xbmc/r $changes" $DEBIAN/changelog.tmp
}


###
# Main
###
    # Load config file
    if ! [ -f $1 ]
    then
        echo "config file not found"
        echo "usage $0 configfile"
        exit 3
    else
        . $1
        echo "#--------------------------#" >> $LOG
        echo "using config file $1 with contents:" >> $LOG
        cat $1 >> $LOG
	[[ -z $RELEASEV ]] && RELEASEV=13.0 && echo "using default Release Version 13.0" >> $LOG
    fi

    date >> $LOG
    CURREV=$(getGitRev $BUILD_REPO)
    updateRepo
    UPSTREAMREV=$(getGitRev $UPSTREAM_REPO/$UPSTREAM_BRANCH)
    echo "CURREV: $CURREV" >> $LOG
    echo "UPSTREAMREV: $UPSTREAMREV" >> $LOG

    if [[ $(compareRevs $CURREV $UPSTREAMREV) == "False" ]] || [[ $FORCE_BUILD == "True" ]]
    then    
        buildPackage
    else
        echo "already at latest revision" >> $LOG
        exit 0
    fi

