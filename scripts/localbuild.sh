#! /bin/sh

#set -x

. $HOME/.myconfig
[ -e $HOME/.mymachine ] && . $HOME/.mymachine

EXTRADIRS=$BUILDEXTRADIRS

die () {
    echo -e $1 >&2
    exit 1
}

usage() {
    echo "$(basename $0) [-s <SYSTEM>|-R <repo>] [-r] [-e <ENV>] [-l|-i|<command>]"
    echo "Options:"
    echo -e "\t-s <SYSTEM> := openSUSE-<version> | SLE.."
    echo -e "\t  or set the BUILDENV environment variable"
    echo -e "\t-l: start interactive shell in local home directory."
    echo -e "\t-i: info only: print buildroot directory."
    echo -e "\t-R <repo>: use <repo> in osc build-root."
    echo -e "\t-r: run as user root."
    echo -e "\t-e <ENV>: add environment setting ENV to command. <ENV> must be of the form FOO=BAR."
    echo -e "\t<command>: run <command> in current directory but in build environment."
    echo -e "If run without command, start interactive shell in current directory."
    echo -e "use BUILDEXTRADIRS to specify extra directories to include in build environment."
    echo -e "use BUILDENVHOME to specify location of build environment."
    exit 0;
}

save_cmdline ()  # <dir_to_put_file> <command_to_save> <command_args> <sudo_or_empty>
{
    local dir=$1
    local cmd=$2
    local cmdargs="$(eval echo $3)"
    local sudo=$4

    cmd="${cmd##*/}"
    cmdline="$cmd $cmdargs"

    [ -z "$dir" -o -z "$cmd" -o -z "$cmdline" ] && return 1;

    if [ -d $dir ]
    then
	if [ -e "$dir/.command_$cmd" -a ! -e "$dir/.command_$cmd.bak" ]
	then
	    $sudo mv "$dir/.command_$cmd" "$dir/.command_$cmd.bak"
	fi
	tmp=$(mktemp /tmp/file-XXXXXX)
	echo $cmdline > $tmp
	$sudo mv $tmp "$dir/.command_$cmd"
    fi
}

all_cleanup() {
    local tmpfile="$1"
    local mount_list="$2"
    local rmdirs="$3"

    [ -n "$tmpfile" ] && rm -f $tmpfile

    for i in $mount_list
    do
	echo "unmounting $i"
	sudo umount  $i
    done

    for i in $rmdirs
    do
	sudo rmdir $i
    done
}

name=$1

infoonly=0
do_root=0

cmd=$0
cmdargs="${1+\"$@\"}"
declare -a env
declare -i env_i=0

while [ -n "$1" ]
do
    cmd=$1
    shift
    case $cmd in
	-*)
	    case $cmd in
		-l)
		    starthome=1 ;;
		-e) env[$env_i]=$1; env_i=$(( $env_i + 1 )); shift ;;
		-s)
		    system="$1"
		    shift
		    ;;
		-i) infoonly=1 ;;
		-r) do_root=1 ;;
		-a) arch=$1; shift ;;
		-R) repo=$1; shift ;;
		*)   usage ;;
	    esac
	    ;;
	*)
	    while [ -n "$cmd" ]
	    # runcommand="${cmd}${*:+ }${*}"
	    do
		if [[ "$cmd" =~ .*[$IFS].* ]]
		then
		    runcommand="${runcommand}${runcommand:+ }\"${cmd}\""
		else
		    runcommand="${runcommand}${runcommand:+ }${cmd}"
		fi
		cmd=$1
		shift
	    done
	    break
	    ;;
    esac
done

[ "$starthome" == "1" -a -n "$runcommand" ] && die "Cannot specify a command with the -l option"
[ "$starthome" == "1" -a "$infoonly" == "1" ] && die "-i (info only) makes no sense with -l"
[ -n "$runcommand" -a "$infoonly" == "1" ] && die "-i (info only) makes no sense with a command to execute"

[ -n "$repo" -a -n "$system" ] && die "Cannot specify -R and -s at the same time"

# FIXME: make arch configurable
if [ -z "$arch" ]; then
    case $(uname -m) in
	i686|i586|i486|i386) arch=i386 ;;
	*) arch=$(uname -m) ;;
    esac
fi

if [ -z "$repo" ]
then
    [ -z "$system" ] && system=$BUILDENV
    [ -z "$system" ] && \
	die "neither build environment sepcified on command line nor BUILDENV environment variable specified"

    name=$system
    case $name in
	home-*)
	    name=$(echo $name | sed -e "s@:@-@")
	    ;;
	openSUSE-*) ;;
	openSUSE:*)
	    name=$(echo $name | sed -e "s@:@-@")
	    ;;
	SLE*)
	    ;;
	SUSE-*)
	    name=${name##SUSE-}
	    ;;
	SUSE:*)
	    name=${name##SUSE:}
	    name=$(echo $name | sed -e "s@:@-@")
	    ;;
	*:*)
	    name=$(echo $name | sed -e "s@:@-@")
	    ;;
	*-*) ;;
	*)
	    die "$system is not a valid build repo name"
	    ;;
    esac

    # if no arch is specified append current arch
    case $name in
	*-i386|*-i586|*-x86_64|*-ppc|*-ppc64|*-ppc64le|*-s390|*-s390x|*-arm*) dir=$name ;;
	*)
	    dir=$name-$arch ;;
    esac

    if [ ! -d ./$dir ]
    then
	if [ -n "$BUILDENVHOME" ]
	then
	    if [ -d $BUILDENVHOME/$dir ]
	    then
		dir=$BUILDENVHOME/$dir
	    else
		die "Neither ./$dir nor $BUILDENVHOME/$dir exist"
	    fi
	else
	    die "./$dir doesn't exist.\n Maybe set \$BUILDENVHOME"
	fi
    fi
else # $repo
    if [ -n "$BUILDROOT" ]
    then
	dir=$BUILDROOT;
    else
	dir="$(osc config general build-root)" || die "Cannot get build-root from osc"
	dir=${dir/*is set to \'/}
	dir=${dir%\'}
    fi
    dir=${dir/\%\(repo\)s/$repo}
    dir=${dir/\%\(arch\)s/$arch}
    if [[ $dir =~ %\(project\)s ]]; then
       project="$(osc info | sed -n 's/Project name: //p')"
    fi
    dir=${dir/\%\(project\)s/$project}
    [ -n "$dir" ] || die "Cannot determine build-root"
    [ -d "$dir" ] || die "build-root $dir doesn't exist"
    [ -d $dir/etc ] || die "Repository $dir is bogus: /etc missing"
    [ -e $dir/etc/passwd ] || die "Repository $dir is bogus: /etc/passwd missing"
    if [ "$do_root" = "0" ]
    then
	user=$(id -u -n)
	line=$(grep "^$user:" $dir/etc/passwd)
	if [ -z "$line" ]
	then
	    line=$(grep "^$user:" /etc/passwd)
	    if [ -z "$line" ]
            then
               line=$(ypcat passwd 2>/dev/null | grep "^$user:")
            fi
	    [ -n "$line" ] || die "user $user not in /etc/passwd"
	    sudo sh -c "echo \"$line\" >> $dir/etc/passwd"
	fi
	OFS=$IFS; IFS=:; set -- $line; IFS=$OFS
	homedir=$6
	if [ ! -d $dir/$homedir ]
	then
	    sudo mkdir -p $dir/$homedir
	    sudo chown $user:$(id -g -n) $dir/$homedir
	fi
    fi
fi
thisdir=$(pwd)

[[ $thisdir =~ .*:.* ]] && {
    echo -en "The execute directory $thisdir contains \':\'.\n"\
         "Building in such a directory may lead to strange results\n" >&2;
    read -p "(y/N)?"  -n 1 result;
    [ "$result" = "y" -o "$result" = "Y" ] || exit 1; }

if [ $infoonly -eq 1 ]
then
    echo $dir
    exit 0
fi

unset tmpfile mount_list rmdirs

trap "wait; all_cleanup \"\$tmpfile\" \"\$mount_list\" \"\$rmdirs\"" EXIT

if [ -z "$runcommand" ]
then
    if [ "$starthome" != "1" ]
    then
	tmpfile=$(mktemp "$dir/tmp/tmp-XXXXXXX")
	cat > $tmpfile <<EOF
#!/bin/sh
cd ${thisdir}
/bin/bash -li
EOF
	chmod u+x $tmpfile
	command="--command=\"/${tmpfile##$dir}\""
    else
	unset command
    fi
else
    tmpfile=$(mktemp "$dir/tmp/tmp-XXXXXXX")
    cat > $tmpfile <<EOF
#!/bin/sh
cd \$1
trap "test -n \"\\\$_PID\" && kill -15 \\\$_PID" EXIT
set -x
EOF
    for (( i=0 ; $i - ${#env[@]} ; i++))
    do
	echo "export ${env[$i]}" >> $tmpfile
    done
    cat >> $tmpfile <<EOF
$runcommand &
set +x
_PID=\$!
wait
trap "" EXIT
EOF
    chmod u+x $tmpfile
    command="--command=\"${tmpfile##$dir} ${thisdir}\""
fi


if [ "$do_root" = "0" ]
then
    [ -z "$homedir" ] && homedir=$(grep $USER $dir/etc/passwd | awk -F":" ' {print $6;}')
    [ -z "$homedir" ] && die "Missing or wrong homedir $homedir"
    [ ! -d $dir/$(dirname $homedir) ] && die "Missing or wrong homedir $homedir"
    [ -n "$homedir" -a ! -d $dir/$homedir ] && sudo mkdir $dir/$homedir
else
    unset homedir
fi

for i in $homedir /proc /sys /dev /dev/shm $EXTRADIRS
do
    this=$(readlink -f $dir/$i)
    [ -z "$this" ] && this=$dir/$i
    entry=$(mount | cut -d' ' -f 3 | grep $this\$)
    if [ -z "$entry" ]
    then
	[ -d $this ] || sudo mkdir -p $this
	echo "mounting $this"
	sudo mount -obind /$i $this && mount_list="$this $mount_list"
    fi
done

if [ -n "$thisdir" ]
then
    if [ ! -d $dir/$thisdir ]
    then
	tmp=$thisdir
	while [ "$tmp" != "/" ]
	do
	    last=$tmp
	    tmp=${tmp%/*}
	    if [ -d $dir/$tmp ]
	    then
		break;
	    fi
	done
	ls $dir$last
	if [ -n "$last" -a ! -d $dir$last ]
	then
	    sudo mkdir $dir/$last && rmdirs="$dir/$last $rmdirs"
	    echo "mounting $last"
	    sudo mount -o bind $last $dir/$last && mount_list="$dir/$last $mount_list"
	fi
    fi
fi

[ -z "$homedir" ] && { homedir=root; USER=root; }
sudo sh -c "HOME=$homedir chroot $dir su - $USER $command"

ret=$?
    if [ $ret -ne 0 -a -n "$tmpfile" ]
    then
	cat $tmpfile
    fi

#sudo sh -c "HOME=/home/eich chroot --userspec=$UID:$GROUPS $dir  $SHELL -il"

test $ret -eq 0 && save_cmdline . "$cmd" "$cmdargs" ""

# Cleanup done by EXIT trap
exit $ret
