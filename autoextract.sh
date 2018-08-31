#!/bin/bash
set -e

exclude_file="$HOME/scripts/shell/extractexclude.txt"
store_config="$HOME/scripts/shell/extractdir.txt"
album_config="$HOME/scripts/shell/extractalbumdir.txt"
list_content="/tmp/content.txt"

video_exts=("*.avi" "*.mp4" "*.mov" "*.wmv" "*.rmvb" "*.mkv" "*.flv" "*.mpg" "*.MP4" "*.AVI" "*.MOV" "*.WMV" "*.RMVB" "*.MKV" "*.FLV" "*.MPG")
image_exts=("*.jpg" "*.jpeg" "*.png" "*.bmp" "*.JPG" "*.JPEG" "*.PNG" "*.BMP")

video_path_pattern="\\.(mp4|avi|mov|wmv|rmvb|mpg|mkv|flv)$"
image_path_pattern="\\.(jpg|png|jpeg|bmp)$"
escape_chars=("\\(" "\\)" "\\[" "\\]" "&" "\\}" "{" "\\$" "^" "~" "!" "\\\`" "\\\"" "'")

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
    
    # Can't extract to the same folder whith archive file
    if [[ $out_dir == $(pwd) ]]; then
        out_dir="$out_dir/out"
    fi

    echo "$out_dir"
}

# return the save path
check_store(){
    local cur_dir   
    local file_count
    local code

    cur_dir=$(cat "$store_config")
    file_count=0

    for i in "$cur_dir"/*
    do
        if [[ -f $i ]]; then
            file_count=$(( file_count + 1 ))
        fi
    done

    if [[ $file_count -gt 55 ]]; then
        read -er -p "The $cur_dir dir is full, please give a new path: " new_path

        if [ ! -d "$new_path" ]; then
            mkdir -p "$new_path"
        fi

        code=$?

        if [[ $code -eq 0 ]]; then
           echo "$new_path" | tee "$store_config"
        else
            echo "$cur_dir"
            return 1
        fi
    else
        echo "$cur_dir"
    fi
}

# $1 file_name
check_custom_dir(){    
    if [[ "$1" == *"@custom"* ]]; then
        if [[ $assing_dir != '' ]]; then
            echo "$assing_dir"
        else        
            read -er -p "Set the new path: " new_dir
            echo "$new_dir"
        fi
    else
        local store_path
        store_path=$(check_store)
        echo "$store_path"
    fi
}

# $1 dir path
check_dir(){
    local check_path
    
    check_path="${1//\\/}"

    if [[ "$check_path" == '' ]]; then
        echo -e 'bad path !\n'
        return 1;
    elif [[ ! -d "$check_path" ]]; then
        mkdir -p "$check_path"
    fi

    return $?
}

# return the alumb store path
check_album(){
    local cur_dir 
    local file_count
    local code

    cur_dir=$(cat "$album_config")
    file_count=0

    for i in "$cur_dir"/*
    do
        if [[ -d $i ]]; then
            file_count=$(( file_count + 1 ))
        fi
    done

    if [[ $file_count -gt 55 ]]; then
        read -er -p "he dir:${cur_dir} is full. give a new path: " new_path

        if [[ ! -d "$new_path" ]]; then
            mkdir -p "$new_path"
        fi

        code=$?

        if [[ $code -eq 0 ]]; then
           echo "$new_path" | tee "$album_config"
        else
            echo ""
        fi
    else
        echo "$cur_dir"
    fi
}

# $1 file_name
# $2 password
# $3 partten
# $4 dir
extract_file() {
    local exts_parrtern=( "$3" )
    local excludes
    local exec_cmd

    if [[ "$1" == *'.rar' ]]; then
        exec_cmd="unrar -or -p$2 -x@$exclude_file e $1 ${exts_parrtern[*]} $4"
    elif [[ "$1" == *'.zip' ]]; then
        excludes=$(sed ':a ; N;s/\n/ / ; t a ; ' "$exclude_file")
        exec_cmd="unzip -P$2 -Ocp936 -j $1 ${exts_parrtern[*]} -x $excludes  -d $4"
    elif [[ "$1" == *'.7z' ]]; then
        exec_cmd="7za -p$2 -o$4 -x@$exclude_file e $1 ${exts_parrtern[*]} -sccUTF-8 -aot -r"
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
        file_name=$(eval "unrar -p$2 -x@$exclude_file lb $1 ${video_exts[*]} ${image_exts[*]} | head -n 1")
        file_name=$(format_extract_name "$file_name")
        timeout -s9 0.5 unrar -p"$2" -x@"$exclude_file" p "$1" "*$file_name" > /dev/null
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

    if [[ "$1" == *'.rar' ]]; then
        exec_cmd="unrar -p$2 -x@$exclude_file lb $1 ${video_exts[*]} ${image_exts[*]}"
    elif [[ "$1" == *'.zip' ]]; then
        exec_cmd="unzip -P$2 -Ocp936 -l $1 ${video_exts[*]} ${image_exts[*]} | sed -n '4,/---------/p' | while read -r _ _ _ c4; do echo \$c4; done"
    elif [[ "$1" == *'.7z' ]]; then
        exec_cmd="7za -slt -p$2 -x@$exclude_file l $1 ${video_exts[*]} ${image_exts[*]} -r -sccUTF-8 | sed -n 's/Path = //gp'"
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

    case $target in
        "sjry") arr_password=("sjry") ;;
        "1024") arr_password=("1024") ;;
        "taotujie") arr_password=("www.taotufabu.com") ;;
        "situge") arr_password=("www.yixiumi.com" "www.situge.com" "situge") ;;
        "sifangclub") arr_password=("sifangclub.com" "sifangclub1.com" "sfjulebu.com" "sifangclub.net") ;;
        "lululu") arr_password=("lululu.cc" "lululu.lu" "qunalu.cc") ;;
        *) arr_password=() ;;
    esac

    arr_length=${#arr_password[@]}

    if [[ $arr_length -eq 0 ]]; then
        echo ""
        return 1
    fi

    if [[ $arr_length -eq 1 ]]; then
        echo "${arr_password[0]}"
        return 0
    fi

    # shellcheck disable=2068
    for i in ${arr_password[@]}; do
        code=$(extract_test "$1" "$i" && echo $?)

        if [[ $code -eq  0 ]]; then
            echo "$i"
            return 0
        fi
    done

    # no one can matched then do it
    echo "";
}

# $1 file_name
del_file(){
    if [[ $non_delete == true ]]; then
        return 0;
    fi

    local rm_file
    local find_path

    rm_file="${1%.*}"
    rm_file="${rm_file//part*/part*}.${1##*.}" 
    find_path=$(pwd)

    if [[ $auto_del == true ]]; then
        echo -e "Moving to trash, use trash-list to review !\\n"
        
        find "$find_path" -name "$rm_file" -exec trash-put {} \;

        if [[ -f "$1" ]]; then
            rm -i "$rm_file";
        fi
    else
        find "$find_path"  -name "$rm_file" -exec rm -i {} \;
    fi 
}

# $1 file_name
# $2 password
extract_pic(){
    msg "Image checking, pleas wait for a moment !\\n"

    local pic_count

    pic_count=$(sandbox "grep -c -i -E \"$image_path_pattern\" \"$list_content\"")

    if [[ $pic_count -gt 10 ]]; then
        head -n 20 $list_content 

        if [[ $auto_extr_pic != true ]]; then
            read -er -p "There are $pic_count pictures. going to extract?" r_look

            if [[ $r_look != 'y' && $r_look != 'yes' ]]; then
                del_file "$1"
                return 0;
            fi
        fi

        msg --prompt "Current file name: $1 \\n"

        if [[ $assing_dir != '' ]]; then
            msg --warn "Warn, you had set parent dir :$assing_dir \\n That will be output to here! \\n"
        fi

        read -er -p "Set the path and exts_parrtern:" r_path r_ext

        local save_path

        if [[ $assing_dir != '' ]]; then
            save_path="$assing_dir/$r_path"
        else
            save_path="$r_path"
        fi

        save_path=$(format_save_dir "$save_path")

        local code

        code=$(check_dir "$save_path" && echo $?)

        if [[ $code -ne 0 ]]; then
            return "$code"
        fi

        if [[ "$r_ext" == "" ]]; then
            extract_file "$1" "$2" "${image_exts[*]}" "$save_path"
        else
            extract_file "$1" "$2" "$r_ext" "$save_path"   
        fi     

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

    extract_list "$1" "$pwd" > /dev/null

    local count

    count=$(sandbox "grep -i -c -E \"$video_path_pattern\" \"$list_content\"")

    if [[ $count -eq 0 || $only_extrac_pic == true ]]; then
        msg --prompt "No media files !\\n"
        extract_pic "$1" "$pwd"
        return 0;
    fi

    local file_path

    file_path=$(sandbox "grep -i -E \"$video_path_pattern\" \"$list_content\"" | head -n 1)

    local dir_name

    if [[ $target == 'lululu' ]]; then
        dir_name="${1%%.*}"
    elif [[ $target == 'sjry' ]]; then
        dir_name=$(dirname "$file_path" | gawk -F'/' '{print $NF}')
        if [[ $dir_name == '.' ]]; then
            dir_name="${dir_name%.*}"
        fi
    else
        dir_name=$(basename "$file_path")
        dir_name="${dir_name%.*}"
    fi

    dir_name="${dir_name// /_}"

    local exp_dir
    local check_album_dir
    local code
    local file_name
    local extract_pattern
    local ext
    local new_file_name

    if [[ $count -gt 1 ]]; then
        if [[ "$assing_dir" != "" ]]; then
            exp_dir=$(format_save_dir "$assing_dir")
        else
            check_album_dir=$(check_album)
            exp_dir="$check_album_dir/$dir_name"

            read -er -p "There are more then one media file, would you like extract to here :$exp_dir " r_answered

            if [[ $r_answered != 'y' && $r_answered != 'yes' && $r_answered != '' ]]; then
                grep -i -E "$video_path_pattern" "$list_content"
                read -er -p "Please give the new path :" exp_new_path
                exp_dir=$(format_save_dir "$exp_new_path")
            fi            
        fi

        code=$(check_dir "$exp_dir" && echo $?)

        if [[ $code -ne 0 ]]; then
            msg --error "Check faile save dir ! \\n"
            return "$code"
        fi

        extract_file "$1" "$pwd" "${video_exts[*]}" "$exp_dir"
        
        ls -l --block-size=M "$exp_dir"
    else
        msg --prompt "file: $1 ! \\n Current extract to: $file_path \\n"

        exp_dir=$(check_custom_dir "$1")
        exp_dir=$(format_save_dir "$exp_dir")
        code=$(check_dir "$exp_dir")

        if [[ $code -ne 0 ]]; then
            return "$code"
        fi

        file_name=$(basename "$file_path")
        extract_pattern="*"$(format_extract_name "$file_name")
        ext=$(echo "${file_name##*.}" | tr '[:upper:]' '[:lower:]')
        new_file_name=$(echo "$dir_name.$ext" | sed "s/ //g;s/[\\!\\,\\']*//g;s/@custom//g")
        
        extract_file "$1" "$pwd" "$extract_pattern" "$exp_dir"

        if [[ "$file_name" != "$new_file_name" ]]; then
            mv "$exp_dir/$file_name" "$exp_dir/$new_file_name"
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
        output=*) assing_dir=$(format_save_dir "${OPTARG//output=/}") ;;
        trash) auto_del=true ;;
        pwd=*) epassword="${OPTARG//pwd=/}" ;;
        pic) auto_extr_pic=true ;;
        onlypic) only_extrac_pic=true ;;
        nodel) non_delete=true ;;
    esac
done

if [[ "$epassword" == '' && "$target" == '' ]]; then
    msg --error "Please set the target or give a password ! \\n"
    exit 1
fi

shift $(( OPTIND - 1 ))

while [[ -n "$1" ]]; do
    main "$1"
    shift
done