#! /bin/bash

usage() {
    echo -en "$(basename $0) [-h|-?|--help|filelist...]\n"
    echo -en "Options:\n"
    echo -en "   -h|-?|--help: Usage\n"
    echo -en "Either specify filelist or set environment variable \"PATCHSET\"\n"
}

while [ -n "$1" ]; do
    case $1 in
	-h|-?|--help) usage; exit 0 ;;
	*) files+=" $1"; shift ;;
    esac
done

if [ -z "$files" -a -z "$PATCHSET" ]; then
    usage
    exit 1
elif [ -z "$files" ]
    files=$PATCHSET
fi

cd src/*
dir=$(basename $PWD)
for i in $files; do
    echo $i
    git am -p1 --ignore-whitespace --directory $dir < ../../$i
    if [ $? -ne 0 ]; then
	patch -p1 -l --forward < ../../$i
	if [ $? -eq 0 ]; then
	    OFS=$IFS
	    IFS="
"
	    for i in $(git status -s); do
		case $i in
		    ' 'M' '*|' 'A' '*) git add ${i# [AM] } ;;
		    ' 'D' '*) git rm ${i# [AM] } ;;
		esac
	    done
	    IFS=$OFS
	    git am --continue
	else
	    echo "Failed - starting shell"
	    echo "When conflicts are resolved run"
	    echo "git add/rm file; git am --continue"
	    echo "or if you prefer to skip the patch"
	    echo "git am --abort"
	    echo "... and exit shell"
	    echo "Files changed:"
	    git status -s
	    bash;
	fi
    fi
done
