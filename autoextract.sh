#!/bin/bash
set -e
declare target
declare assing_dir
declare auto_del=false
declare epassword
declare only_extrac_pic=false
declare non_delete=false

declare -r list_content="/tmp/content.txt"
declare -r config_dir="$HOME/.extract_config"
declare -r config_file="$config_dir/extract.config"

declare -r video_exts=("*.avi" "*.mp4" "*.mov" "*.wmv" "*.rmvb" "*.mkv" "*.flv" "*.mpg" "*.MP4" "*.AVI" "*.MOV" "*.WMV" "*.RMVB" "*.MKV" "*.FLV" "*.MPG")
declare -r image_exts=("*.jpg" "*.jpeg" "*.png" "*.bmp" "*.JPG" "*.JPEG" "*.PNG" "*.BMP")

declare -r video_path_pattern="\\.(mp4|avi|mov|wmv|rmvb|mpg|mkv|flv)$"
declare -r image_path_pattern="\\.(jpg|png|jpeg|bmp)$"
declare -r escape_chars=("\\(" "\\)" "\\[" "\\]" "&" "\\}" "{" "\\$" "^" "~" "!" "\\\`" "\\\"" "'")

init(){
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$HOME/.extract_config"
    fi

    if [[ -f "$config_file" ]]; then
        while read -r line; do
            case $line in
                exclude=*) export exclude_file="${line//exclude=/}" ;;
                video_album_store=*) export video_album_dir="${line//video_album_store=/}" ;;
                video_store=*) export video_save_dir="${line//video_store=/}" ;;
                image_store=*) export image_save_dir="${line//image_store=/}" ;;
                password_file=*) export password_file="${line//password_file=/}" ;;
            esac
        done < "$config_file"
    fi
}

msg(){
    local msg_type
    local args

    args=$(getopt -o ewp -l error,warn,prompt -- "$@")

    eval set -- "$args"

    while [[ -n "$1" ]]; do
        case "$1" in
            "-e"|"--error") msg_type="error" ;;
            "-w"|"--warn") msg_type="warn" ;;
            "-p"|"--prompt") msg_type="prompt" ;;
            "--") shift && break ;;
        esac 
        shift
    done

    case $msg_type in
        "warn") echo -e "\\033[33m$1\\033[0m" ;;
        "error") echo -e "\\033[31m$1\\033[0m" ;;
        "prompt") echo -e "\\033[34m$1\\033[0m" ;;
        *) echo  -e "$1";
    esac
}
# $1 the eval command
sandbox(){
    set +e
    eval "$1"
    set -e
}

# $1 the file name
file_info(){
    msg --prompt "Extracting File: $1"
    file "$1"
}

# $1 file_name
format_extract_name() {
    local new_file_name

    new_file_name=$1

    # shellcheck disable=SC2068
    for char in ${escape_chars[@]}; do
        new_file_name="${new_file_name//$char/*}"
    done

    echo "${new_file_name// /*}"
}

# $1 dir path
format_save_dir() {
    local out_dir

    out_dir=$(echo "$1" | sed 's/\/*$//g')

    # shellcheck disable=SC2068
    for char in ${escape_chars[@]}; do
        out_dir="${out_dir//$char/$char}"
    done

    echo "$out_dir"
}

# $1 dir path
check_dir(){
    local check_path

    if [[ "$check_path" != "" && ! -d "$check_path" ]]; then
        mkdir -p "$check_path"
        echo "0"
    else
        echo "1"
    fi
}

get_dir() {
    local dir_path

    while [[ ! -d "$dir_path" ]]; do
        read -er -p "please give a new path: " dir_path

        if [[ $(check_dir "$dir_path") -eq 0 ]]; then
            break;
        fi
    done

    echo "$dir_path"
}

# return the save path
check_store(){
    local cur_dir   

    cur_dir="$1"

    if [[ $(check_dir "$cur_dir") -ne 0 ]]; then
        cur_dir=$(get_dir)
    fi

    while [[ $(sandbox "find \"$cur_dir\" -maxdepth 1 -printf %P\\\\n | grep -ic \"^[^\\\\.]\"") -gt 56 ]]; do
        msg --warn "the path is full"
        cur_dir=$(get_dir)
    done

    echo "$cur_dir"
}

# $1 file_name
# $2 password
# $3 partten
# $4 dir
extract_file() {
    local exts_parrtern=( "$3" )
    local excludes
    local exec_cmd

    if [[ -f exclude_file ]]; then
        if [[ "$1" == *'.zip' ]]; then
            excludes=" -x "$(sed ':a ; N;s/\n/ / ; t a ; ' "$exclude_file")
        elif [[ "$1" == *'.rar' || "$1" == *'.7z' ]]; then
            excludes=" -x@\"$exclude_file\""
        fi
    fi 

    if [[ "$1" == *'.rar' ]]; then
        exec_cmd="unrar -or -p\"$2\"$excludes e $1 ${exts_parrtern[*]} $4"
    elif [[ "$1" == *'.zip' ]]; then
        exec_cmd="unzip -P$2 -Ocp936 -j $1 ${exts_parrtern[*]} $excludes  -d $4"
    elif [[ "$1" == *'.7z' ]]; then
        exec_cmd="7za -p\"$2\" -o\"$4\"$excludes e $1 ${exts_parrtern[*]} -sccUTF-8 -aot -r"
    else
        echo 'unkonw file'
        return 1;
    fi
    
    sandbox "$exec_cmd"
    return $?
}

# $1 file_name
# $2 password
extract_test() {
    local code
    local file_name

    if [[ "$1" == *'.rar' ]]; then
        file_name=$(eval "unrar -p$2 lb $1 ${video_exts[*]} ${image_exts[*]} | head -n 1")
        file_name=$(format_extract_name "$file_name")
        timeout -s9 0.5 unrar -p"$2" p "$1" "*$file_name" > /dev/null
    elif [[ "$1" == *'.7z' || "$1" == *'.zip' ]]; then
        file_name=$(eval "7za -p$2 l $1 ${video_exts[*]} ${image_exts[*]} -r -slt -sscUTF-8 | sed -n '20{s/Path = //p}'")
        file_name=$(format_extract_name "$file_name")
        timeout -s9 0.5 7za -p"$2" t "$1" "$file_name" -r > /dev/null
    else
        return 1; 
    fi

    code=$?

    # 137 -> the timeout signal
    if [[ $code -eq 137 || "$code" == '' ]]; then
        return 0
    else
        return "$code"
    fi
}
# $1 file_name
# $2 password
extract_list() {
    local exec_cmd
    local excludes
    local videoext
    local imgext

    videoext="${video_exts[*]}"
    videoext="${videoext//\*/\\*}"
    imgext="${image_exts[*]}"
    imgext="${imgext//\*/\\*}"

    if [[ -f exclude_file ]]; then
        if [[ "$1" == *'.zip' ]]; then
            excludes=" -x "$(sed ':a ; N;s/\n/ / ; t a ; ' "$exclude_file")
        elif [[ "$1" == *'.rar' || "$1" == *'.7z' ]]; then
            excludes=" -x@\"$exclude_file\""
        fi
    fi 
    
    if [[ "$1" == *'.rar' ]]; then
        exec_cmd="unrar -p\"$2\"$excludes lb $1 $videoext $imgext"
    elif [[ "$1" == *'.zip' ]]; then
        exec_cmd="unzip -P$2 -Ocp936 -l $1 $videoext $imgext $excludes | sed -n '4,/---------/p' | while read -r _ _ _ c4; do echo \$c4; done"
    elif [[ "$1" == *'.7z' ]]; then
        exec_cmd="7za -slt -p\"$2\"$excludes l $1 $videoext $imgext -r -sccUTF-8 | sed -n 's/Path = //gp'"
    else
        echo 'unkonw file'
        return 1; 
    fi
    sandbox "$exec_cmd | tee $list_content"
    return $?
}

get_pwd() {
    if [[ $epassword != '' ]]; then
        echo "$epassword"
        return 0
    fi

    local arr_password
    local arr_length
    local password

    if [[ "$target" != "" && -f "$password_file" ]]; then
        # the key is uniq
        password=$(sed -n "s/^$target=//gp" "$password_file" | head n -1)
    fi

    if [[ "$password" != "" ]]; then
        read -r -a arr_password <<< "$password"
    else
        arr_password=()
    fi

    arr_length=${#arr_password[@]}

    if [[ $arr_length -eq 0 ]]; then
        read -er -p "give a password:" -s new_password
        echo "$new_password"
    elif [[ $arr_length -eq 1 ]]; then
        echo "${arr_password[0]}"
    else
        for ((i=0; i<arr_length; i++)); do
            code=$(extract_test "$1" "${arr_password[i]}" && echo $?)

            if [[ $code -eq  0 ]]; then
                echo "${arr_password[i]}"
                return 0;
            fi
        done
        return 1
    fi
    return 0
}

# $1 file_name
del_file(){
    if [[ $non_delete == true ]]; then
        return 0;
    fi

    local rm_file

    rm_file="${1%.*}"
    rm_file="${rm_file//part*/part*}.${1##*.}" 

    if [[ $auto_del == true ]]; then
        msg "Moving to trash, trash-list to review !\\n"
        
        sandbox "trash-put $rm_file"
    else
        sandbox "rm -i $rm_file"
    fi 
}
# file path
get_basedir(){
    local file_path

    file_path="$1"

    local dir_name

    if [[ $target == 'lululu' ]]; then
        dir_name="${1%%.*}"
    elif [[ $target == 'sjry' ]]; then
        dir_name=$(dirname "$file_path" | awk -F'/' '{print $NF}')
        if [[ $dir_name == '.' ]]; then
            dir_name="${dir_name%.*}"
        fi
    else
        dir_name=$(basename "$file_path")
        dir_name="${dir_name%.*}"
    fi

    echo "${dir_name// /_}"
}

# $1 file_name
# $2 password
extract_pic(){
    local pic_count
    local file_path
    local dir_name
    local save_path

    msg "Image checking, pleas wait for a moment !\\n"
    pic_count=$(sandbox "grep -c -i -E \"$image_path_pattern\" \"$list_content\"")

    if [[ $pic_count -gt 10 ]]; then
        file_path=$(grep -i -E "$image_path_pattern" "$list_content" | head -n 20 | tee | head -n 1)
        dir_name=$(get_basedir "$file_path")

        if [[ $assing_dir != '' ]]; then
            save_path="$assing_dir/$dir_name"
        elif [[ -d "$image_save_dir"  ]]; then
            save_path="$image_save_dir/$dir_name"
        else 
            save_path="$(pwd)/$dir_name"
        fi

        msg --warn "Confim the save path $save_path \\n"

        read -er -p "[y]es or [n]ew or [e]xit:" confirm

        case $confirm in
            n|new) 
                save_path=$(get_dir)
                ;;
            e|exit)
                del_file "$1"
                return 0
                ;;
            *) 
                if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
                    msg --error "unkonw confirm !\\n"
                    return 1
                fi
                ;;
        esac

        save_path=$(format_save_dir "$save_path")
        check_dir "$save_path"

        extract_file "$1" "$2" "${image_exts[*]}" "$save_path" 
        del_file "$1"
    else
        msg --prompt "there are no more pictures ! \\n"
        del_file "$1"
    fi
}

# $1 file name
main() {
    if [[ ! -f "$1" ]]; then
        return 0;
    fi

    file_info "$1"

    local pwd

    pwd=$(get_pwd "$1")

    if [[ $pwd == '' ]]; then
        msg --error 'No password !'
        return 1
    fi

    msg --prompt "\\nstart extract ================================>"

    extract_list "$1" "$pwd" > /dev/null

    local count

    count=$(sandbox "grep -i -c -E \"$video_path_pattern\" \"$list_content\"")

    if [[ $count -eq 0 || $only_extrac_pic == true ]]; then
        msg --prompt "No media files !\\n"
        extract_pic "$1" "$pwd"
        return 0;
    fi

    local file_path
    local dir_name

    file_path=$(sandbox "grep -i -E \"$video_path_pattern\" \"$list_content\"" | head -n 1)
    dir_name=$(get_basedir "$file_path")

    local exp_dir
    local code
    local file_name
    local extract_pattern
    local ext
    local new_file_name

    if [[ $count -gt 1 ]]; then
        if [[ -d "$assing_dir" ]]; then
            exp_dir=$(check_store "$assing_dir")"/$dir_name"
        else
            exp_dir=$(check_store "$video_album_dir")"/$dir_name"           
        fi
        
        msg --warn "There are more then one media file. Confirm save path: $exp_dir"

        read -er -p "[y]es or [n]ew or [e]xit" answer

        case $answer in 
            n|new)
                exp_dir=$(check_store "") 
                ;;
            e|exit)
                extract_pic "$1" "$pwd"
                return 0
                ;;
             *) 
                if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
                    msg --error "unkonw confirm !\\n"
                    return 1
                fi
                ;;
        esac

        exp_dir=$(format_save_dir "$exp_dir")
        extract_file "$1" "$pwd" "${video_exts[*]}" "$exp_dir"
        
        ls -l --block-size=M "$exp_dir"
    else
        exp_dir=$(check_store "$video_save_dir")
        exp_dir=$(format_save_dir "$exp_dir")

        file_name=$(basename "$file_path")
        extract_pattern="*"$(format_extract_name "$file_name")
        ext=$(echo "${file_name##*.}" | tr '[:upper:]' '[:lower:]')
        new_file_name=$(echo "$dir_name.$ext" | sed "s/ //g;s/[!,']//g")
        
        extract_file "$1" "$pwd" "$extract_pattern" "$exp_dir"

        if [[ "$file_name" != "$new_file_name" ]]; then
            mv "${exp_dir//\\/}/$file_name" "${exp_dir//\\/}/$new_file_name"
        fi
        
        file "$exp_dir/$new_file_name"
    fi

    extract_pic "$1" "$pwd"
}

while getopts :D: opt; do
    if [[ "$opt" != "D" ]]; then
        continue
    fi

    # shellcheck disable=SC2214
    case $OPTARG in
        tag=*) target="${OPTARG//tag=/}" ;;
        output=*) assing_dir="${OPTARG//output=/}" ;;
        trash) auto_del=true ;;
        pwd=*) epassword="${OPTARG//pwd=/}" ;;
        onlypic) only_extrac_pic=true ;;
        nodel) non_delete=true ;;
    esac
done

if [[ "$epassword" == '' && "$target" == '' ]]; then
    msg --error "Please set the target or give a password ! \\n"
    exit 1
fi

shift $(( OPTIND - 1 ))

init # initialize environment

while [[ -n "$1" ]]; do
    main "$1"
    shift
done