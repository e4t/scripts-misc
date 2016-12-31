#! /bin/sh

EXTRADIRS=/space

#set -x

[ -e ~/.mymachine ] && . ~/.mymachine

[ -n "$SPACEDIR" ] && EXTRADIRS=$SPACEDIR

die () {
    echo $1 >&2
    exit 1
}

usage() {
    echo "$(basename $0) [-a <arch>] [-r <repository>] [-d <directory>] [-n] <PRODUCT> [POST]"
    echo "Options:"
    echo -e "\t-a <arch>: select architecture: i586, x86_64"
    echo -e "\t-r <repository>: set repository, default: standard"
    echo -e "\t-d <directory>: use alternate directory for build env"
    echo -e "\t-n: do not strip trailing _* from target"
    echo -e "\t<PRODUCT>: product name: openSUSE-13.2, SLE-12-SP1, etc."
    echo -e "\tPOST: For SLE - if not to be included in the product name"
    echo -e "\t      - GA Update Update:Test (default: GA)"
    exit 0
}

cmd=$0
cmdargs="${1+\"$@\"}"

nostrip=false
while [ -n "$1" ]
do
    arg=$1
    shift
    case $arg in
	-a) arch=$1; shift ;;
	-r) repository=$1; shift ;;
	-d) directory=$1; shift ;;
	-n) nostrip=true ;;
	-*) usage ;;
	*)
	    if [ -n "$name" ]
	    then
		post=$arg
	    else
		name=$arg;
	    fi
	    ;;
    esac
done

[ -z "$name" ] && usage
file=$name
name=${name##*/}
name=${name%.desc}

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

parse_name() {
    local local_name new_name old_name
    local_name=$1
    case $local_name in
	home:*:branches*)
	    new_name=$(echo $local_name | sed -e "s@[^:]\+:[^:]\+:[^:]\+:@@")
	    owner=$(echo $local_name | sed -e "s@[^:]\+:\([^:]\+\).*@\1@")
	    oldname=$local_name
	    parse_name $new_name
	    name=home-$owner-branches-$name
	    target=$oldname
	    ;;
	home:*)
	    new_name=$(echo $local_name | sed -e "s@[^:]\+:[^:]\+:@@")
	    owner=$(echo $local_name | sed -e "s@[^:]\+:\([^:]\+\).*@\1@")
	    oldname=$local_name
	    parse_name $new_name
	    name=home-$owner-$name
	    target=$oldname
	    ;;
	openSUSE-*)
	    api=https://api.opensuse.org
	    target=$(echo $name | sed -e "s@-@:@g")
	    name=$local_name
	    post=
	    ;;
	openSUSE:*)
	    api=https://api.opensuse.org
	    target=$local_name
	    name=$(echo $local_name | sed -e "s@:@-@g")
	    post=
	    ;;
	SLE*)
	    target="SUSE:$local_name"
	    name=$local_name
	    api=https://api.suse.de
	    if [ -z "$post" ]
	    then
		post=":GA"
	    else
		post=":$post"
	    fi
	    ;;
	SUSE-*)
	    target=$(echo $local_name | sed -e "s@-@:@g")
	    name=${local_name##SUSE-}
	    api=https://api.suse.de
	    if [ -z "$post" ]
	    then
		post=":GA"
	    else
		post=":$post"
	    fi
	    ;;
	SUSE:*)
	    target=$local_name
	    name=${local_name##SUSE:}
	    api=https://api.suse.de
	    if [ -z "$post" ]
	    then
		post=":GA"
	    else
		post=":$post"
	    fi
	    ;;
	*:*)
	    api=https://api.opensuse.org
	    target=$local_name
	    name=$(echo $local_name | sed -e "s@:@-@")
	    post=
	    ;;

	*)
	    die "Wrong or missing argument"
	    ;;
    esac
    # clip last _* from $target: this may be used to distinguish things locally
    $nostrip || target=${target%_*}
}

set_passwd_get_home()
{
    local builddir=$1
    local entry passwd name uid gid tmpfile entry home

    if [ -d $builddir -a -e $builddir/etc/passwd ]
    then
	entry=$(grep $USER $builddir/etc/passwd)

	if [ -z "$entry" ]
	then
	    passwd=$(cat /etc/passwd | grep "^$USER:")

	    if [ -z "$passwd" ]
	    then
		passwd=$(ypcat passwd 2>/dev/null | grep "^$USER:")
	    fi

	    if [ -z "$passwd" ]
	    then
		name=$(id -rnu)
		uid=$(id -ru)
		gid=$(id -rg)
		passwd="$name:x:$uid:$gid::$HOME:$SHELL"
	    fi

	    if [ -n "$passwd" ]
	    then
		tmpfile=$(mktemp /tmp/passwd-XXXXXXXXX)
		cat $builddir/etc/passwd >> $tmpfile
		echo "$passwd" >> $tmpfile
		cnt=3
		sudo mv $tmpfile $builddir/etc/passwd || { rm $tmpfile; echo "Cannot add passwd entry"; exit 1; }
	    else
		echo "Cannot copy passwd entry" >&2
	    fi
	    entry=$passwd
	fi

	if [ -n "$entry" ]
	then
	    home=$(echo "$entry" | sed "s/.*:.*:.*:.*:.*:\(.*\):.*/\\1/")
	    home=${home%/*}
	else
	    home=/home
	fi
    fi
    echo $home
}

create_dummy_package() {
    local spec=$1
    local file=$2

    test -e empty.tar || tar -cf empty.tar /dev/null
    cat > $spec <<EOF
#
# spec file for package empty
#

# norootforbuild

Name:           empty
Version:        0.0.0
Release:        0.0
Group:          Development/Libraries/C and C++
License:        X11/MIT
Url:            http://
Summary:        Dummy rpm specfile to create build root
Source0:        empty.tar
EOF

    cat >> $spec < $file

    cat >> $spec <<EOF

BuildRoot:      %{_tmppath}/%{name}-%{version}-build

%description
None
EOF
}

parse_name $name

if [ -z "$arch" ]
then
    arch=$(uname -m)
    case $arch in
	i686|i586|i486|i386) arch=i386 ;;
    esac
fi

if [ -z "$repository" ]
then
    repository="standard"
fi

case $arch in
    i386) oscarch=i586 ;;
    *) oscarch=$arch;
esac

spec=$name.spec

if [ ! -z "$post" -a "$post" != ":GA" ]
then
    middle=${post//:/-}
fi
if [ -n "$middle" ]
then
    case $middle in
	-*) ;;
	*) middle=-${middle} ;;
    esac
fi
if [ -n "$directory" ]
then
    dir=${directory}
else
    dir=${name}${middle}-$arch
fi


if [ -n "$BUILDENVHOME" ]
then
    descdir=$BUILDENVHOME
    builddir=$BUILDENVHOME/$dir
else
    descdir=$(pwd)
    builddir=$(pwd)/$dir
fi

[ "${file%.desc}" == "${file}" ] && file=${name}.desc

if [ ! -e $file ]
then
    if [ -e $descdir/$file ]
    then
	file=$descdir/$file
    else
	file=${directory}.desc
	if [ ! -e $file ]
	then
	    if [ -e $descdir/$file ]
	    then
		file=$descdir/$file
	    else
		die "Create description $name.desc first"
	    fi
	fi
    fi
fi

#test -d $name && { rmdir $name || die "Cannot remove directory $name"; }

trap "rm -f empty.tar" EXIT

create_dummy_package $spec $file

OSC_BUILD_ROOT=$builddir
export OSC_BUILD_ROOT
[ -n "$SPACEDIR" ] && \
    { OSC_PACKAGECACHEDIR=$SPACEDIR/osbuild-packagecache; export OSC_PACKAGECACHEDIR; }

echo "OSC_BUILD_ROOT: $OSC_BUILD_ROOT"
echo "OSC_PACKAGECACHEDIR: $OSC_PACKAGECACHEDIR"
echo "API: $api"
echo "TARGET: ${target}${post} REPOSITORY: $repository"

command="/usr/bin/osc -A $api build --alternative-project=${target}${post} \
     --local-package --no-verify --nochecks  --build-uid=caller \
    $repository $oscarch $spec" # || die "osc build failed $?"
echo "${command}"
${command}
fail=$?

[ $fail -gt 0 ] &&  echo "Warning: osc build failed with $fail"

unset extradirs
for i in $EXTRADIRS
do
    extradirs="$extradirs $builddir/$i"
done

home=$(set_passwd_get_home $builddir)

# Save command line that led to this
save_cmdline "$builddir" "$cmd" "$cmdargs" sudo

sudo mkdir -p $builddir/$home $extradirs
