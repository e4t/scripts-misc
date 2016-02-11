#! /bin/sh

#set -x

CAT=/usr/bin/cat
declare -a NON_UPSTREAM_SIGNATURES=("suse")

usage() {
    echo -en "\n"
    echo -e "Usage:\t$(basename $0) [-m N|n|u|U[<release_number>]|T] [-M \"<mainline message>\"] [-r \"<reference string>\"] [-d <directory>] [<range>]" >&2

    if [ "$flavor" = "xorg" ]
    then
	cat >&2 <<EOF

  Generate an X11:XOrg Patch guideline conformant patch set.
  See also: http://en.opensuse.org/openSUSE:Patches_Guidelines_for_X11:XOrg_Project
EOF
    else
	cat >&2 <<EOF

  Generate a SUSE kernel guideline conformant patch set.
  See also: kerncvs.suse.de:/home/git/kernel-source/README
EOF
    fi

    cat >&2 <<EOF

Options:
  -m The following values are recognized:
     N: "Not applicable"
     n: "never"
     u: "To be upstreamed"
     U  "Upstream", an optional revision string may be specified
     Default: u
  -M <message> will replace the default message generated by the -m option with a 
     different string. This string will be printed in the Patch-mainline: preamble 
     line of the patch.
  -r <sting> an optional reference string. If none is specified the Reference: 
     line in the patch preamble will be left empty.
  -d <directory>: output to directory <directory> instead of the current one.
  -v verbose: print list of files.
  <range> a range of patches. This can either be a single commit or a range of 
     commits like HEAD^^..HEAD. Default is HEAD^..HEAD.
EOF
}

die() {
    echo "$1" >&2
    exit 1
}

get_range() {
    case $1 in
	*..*)
	    range="$range $1"
	    ;;
	*)
	    range="$range $1^..$1"
	    ;;
    esac
    return 0
}

sort_range() {
    local -i  n i swap 
    local dummy a b
    local -a array
    array=($*)
    n=${#array[@]}
    while true
    do
	n=$(( $n - 1 ))
	swap=0
	for (( i=0 ; $i - $n ; i++)) 
	do
	    a=${array[$i]#*..}
	    [ -z "$a" ] && a=HEAD
	    b=${array[$i + 1]#*..}
	    dummy=$(git rev-list $a..$b)
	    if [ -z "$dummy" ]
	    then
		swap=1
		tmp=${array[$i + 1]}
		array[$i + 1]=${array[$i]}
		array[$i]=${tmp}
	    fi
	done
	[ $swap -eq 1 -a $n -gt 1 ] || break
    done
    echo ${array[@]}
}

remove_empty_ranges ()
{
    local -a array
    local -i n i error
    local v val

    error=0

    array=($*)
    n=${#array[@]}
    for ((i=0; $i - $n; i++))
    do
	case ${array[$i]} in
	    *..*) v=$(git rev-list ${array[$i]})
		if [ -z "$v" ]
		then
		    error=1
		    echo "Range ${array[$i]} is empty" >&2
		else
		    val="$val ${array[$i]}"
		fi ;;
	    *) 	val="$val ${array[$i]}" ;;
	esac
    done
    echo $val
    return $error
}

fix_overlaps () {
    local -a array
    local -i n i last
    local  val
    local range start end new_start new_end list
   
    array=($*)
    n=${#array[@]}

    for ((i=0; $n - $i; i++))
    do
	case ${array[$i]} in
	    *..*)
		if [ -n "$start" ]
		then
		    range=${array[$i]}
		    new_start=${range%..*}
		    new_end=${range#*..}
		    val=$(git rev-list $new_start..$end)
		    if [ -n "$val" ]
		    then
		       val=$(git rev-list $new_end..$end)
		       if [ -z "$val" ]
		       then   # overlaps with previous range
			   ${array[$last]}="$start..$new_end"
			   end=$new_ned
		       fi
		       ${array[$i]}=0
		    else
			start=$new_start
			end=$new_end
			last=$i
		    fi
		else
		    range=${array[$i]}
		    start=${range#*..}
		    end=${range%..*} 
		    last=$i
		fi
		continue ;;
	    0)  continue ;;
	    *) 
		if [ -n "$end" ]
		then
		    val=$(git rev-list ${array[$i]}..$end)
		    if [ -n "$val" ]
		    then   # value is embedded
			${array[$i]}=0
			continue
		    fi
		else
		    unset start
		    unset end
		    unset last
		fi
		continue ;;
	esac
    done

    for ((i=0; $i - $n - 1; i++))
    do
	if [ "${array[$i]}" != "0" ]
	then
	    list="$list ${array[$i]}"
	fi
    done
    echo $list
}

get_filename() {
    local commit_id=$1
    local file_name=`git --no-pager show $commit_id --pretty=format:"XTXTXTXT%fXTXTXTXT" |sed -n -e 's#XTXTXTXT\(.*\)XTXTXTXT#\1#p'`
    [ $? -eq 0 ] || return 1
	
#echo $file_name
    file_name=${file_name}.patch
    echo $file_name
    return 0
}

is_upstream_repo() {
    local repo=$1
    shift
    local -a array=($*)
    local -i n=${#array[@]}
    while true
    do
	n=$(( $n - 1 ))
	if [[ "${repo}" =~ "${array[$n]}" ]]
	then
	    return 0
	fi
	[ $n -gt 0 ] || return 1
    done
}

get_git_repo() {
    $(git remote -v  | grep "^origin" | awk '{print $2}' |tail -n1)
}

add_git_repo() {
    local linus_repo="git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux-2.6"
    local repo=""

    repo=$(get_git_repo)
    if [ "${repo}x" != "x" -a "${linus_repo}x" != "${repo}x" ]
    then
	if is_upstream_repo "${repo}" $NON_UPSTREAM_SIGNATURES
	then
	    echo "Git-repo: $repo"
	else
	    echo ""
	fi
    else
	echo ""
    fi
}

suse_filter() {
       ID="$1"
       if [ -z $"$ID" ]
       then 
       	   cat
       else
	   awk "BEGIN { \
                          s=1; p=1; IGNORECASE=1; id=\"${ID}\" }
                /[:space:]*(signed-off-by:|acked-by:|reviewed-by:|tested-by:)/ { \
                          reg=sprintf(\"%s$\", id); \
                          if (\$0 ~ reg) \
                             p=0; \
                          s=0; }
                /^$/ { 
                          if (s == 0) \
                              next; }
                /^---$/ { \
                          if (p == 1) {\
                             if (s == 1) \
                                printf \"\n\";\
                             printf \"Signed-off-by: %s\n\", id; \
                          }
                          p=0; } \
                /^Conflicts:$/ { \
                          if (p == 1) {\
                              printf \"Signed-off-by: %s\n\", id; \
                              printf \"\n\";\
                          }
                          p=0; } \
                      { print; }"
  
       fi
}

if [ -e $HOME/.myconfig ]
then
    . $HOME/.myconfig
else
    if [ -z "$MY_NAME" -o -z "$MY_COMPANY_EMAIL" ]
    then
	echo "Need the env variables $MY_NAME and $MY_COMPANY_EMAIL"
	die "No file $HOME/.myconfig found."
    fi
fi
myid="$MY_NAME <$MY_COMPANY_EMAIL>"

#set -x

case $0 in
    *_xorg.sh)
	flavor=xorg
	;;
    *)
	flavor=kernel
esac

prefix="u"
if [ "$flavor" = "xorg" ]; then
    mainline="to be upstreamed"
else
    mainline="Not yet"
fi
range=


cmd=$1
while [ "$1" ]
do
    cmd=$1
    shift
    case "$cmd" in
	-\?|-h)
	    usage
	    exit 0
	    ;;
	-m)
	    mainline_set=1
	    case "$1" in
		N)
		    prefix="N"
		    mainline="N/A"
		    ;;
		n)  prefix="n"
		    mainline="never"
		    ;;
		u)
		    prefix="u"
		    if [ "$flavor" = "xorg" ] ; then
			mainline="to be upstreamed"
		    else
			mainline="Not yet"
		    fi
		    ;;
		U*)
		    prefix="U"
		    release=${1##U}
		    release=${release##/}
		    mainline="${release:-Upstream}"
		    ;;
		T)
		    prefix="T"
		    mainline="Temporary"
		    ;;
		*)
		    die "Wrong argument for mainline: $1"
		    ;;
	    esac
	    shift
	    ;;
	-M)
	    mainline="$1"
	    shift
	    ;;
	-r)
	    references="$1"
	    shift
	    ;;
	-d)
	    directory="$1"
	    shift
	    ;;
	-v)
	    verbose=1
	    ;;
	-*)
	    die "Wrong option $cmd"
	    ;;
	*)
	    get_range $cmd || die "Cannot get range."
	    shift
	    ;;
    esac
done

if [ -n "$d" -a ! -d "$directory" ]
then
    echo "$directory is not a directory"
    exit 1
fi

if [ -n "$range" ]
then
    range="$(sort_range $range)"
    range="$(remove_empty_ranges $range)" || exit 1
    range="$(fix_overlaps $range)"
else
    range="HEAD^.."
fi

list=$(git rev-list --reverse $range)
max=0
for i in $list
do
    max=$(( $max + 1 ))
done

top=$(git rev-parse --show-toplevel)

# check for remote. Without a remote it's likely that this repo
# is generated by rpm_git. In this case strip off the top directory.
# Note: we should probably let rpm_git set a config entry to clearly
# identify such a repo. (TODO)
if [ -z "$(git config  --get-regexp "remote\..*\.url")" ]
then

    for i in $top/*
    do
	[ -d $i ] || continue

	if [ "z${relative}" != "z" ]
	then
	    unset relative
	    break;
	else
	    relative=${i##*/}
	fi
    done
fi

if [ -z "$directory" -a "$flavor" = "xorg" ]
then
    ls $top/../*.spec &> /dev/null && directory="$(readlink -m $top/..)"
fi

cnt=1
git_repo_tag=$(add_git_repo)
for i in $list
do
    if [ "x$mainline_set" != "x1" ]
    then
	line=$(git log $i^..$i | grep -i "^\s*backported-from: [0-9a-fA-F]\+$")
	id=${line#*: }
	[ -z "$line" ] && id=$i
	string=$(git describe --contains --match 'v*' $id 2>/dev/null)
	if [ -z "$string" ]
	then
	    string=$(git describe --contains $id 2>/dev/null)
	fi
	if [ -n "$string" ]
	then
	    mainline="${string%%~*}"
	    prefix="U"
	else
#           default
	    if [ "$flavor" = "xorg" ]; then
		mainline="to be upstreamed"
	    else
		mainline="Not yet"
	    fi
	    prefix="u"
	fi
    fi
    if [ "$flavor" = "xorg" ]
    then
	cntstr=
	numstr=
	[ $max -gt 1 ] && { cntstr=$(printf " %i/%i" $cnt $max);  numstr=$(printf "%2.2i-" $cnt); };
	subjprefix="[PATCH${cntstr}]"
	filename=${prefix}_${numstr}$(get_filename $i)
	[ $? -eq 0 ] || die "Cannot get filename"
	signedoff="Signed-off-by: $myid%n"
	filter=$CAT
    else
	if [ -z "$directory" ]
	then
	    [ $max -gt 1 ] && die "you have to specify a directory when proecssing more than one commit"
	else
	    filename=$(get_filename $i)
	    [ $? -eq 0 ] || die "Cannot get filename"
	fi
	signedoff=
	filter="suse_filter "'"'$myid'"'
    fi
    [ -z "$git_repo_tag" ] && commit_id="Git-commit: %H%n"
    command="git --no-pager show  ${relative:+--relative=}${relative} --stat -p $i --pretty=format:\"From: %an <%ae>%nDate: %ad%nSubject: ${subjprefix}%s%nPatch-mainline: ${mainline}%n${commit_id}${git_repo_tag}%nReferences: ${references}%n${signedoff}%n%b\""
    if [ -n "$filename" ]
    then
	eval ${command} | eval ${filter} > ${directory:+$directory/}$filename
	if [ "x$verbose" = "x1" ]
	then
	    printlist="${filename}\n${printlist}"
	fi
    else
	eval ${command} | eval ${filter}
    fi
    cnt=$(( $cnt + 1 ))
done
[ -n "$printlist" ] && echo -en "${printlist}"

#		git --no-pager show --stat -p $i --pretty=format:"From: %an <%ae>%nDate: %ad%nSubject: %s%nReferences: ${references}%nPatch-Mainline: ${mainline}%nGit-commit: %H%n${git_repo_tag}%n%nSigned-off-by: $myid%n%n%b" >${directory:+$directory/}$filename
