#!/bin/bash
set -e

# execute arguments
declare target
declare assing_dir
declare auto_del=true
declare epassword
declare only_extrac_pic=false
declare base_name_type
declare list_content
declare -a var_exclude

declare -r config_dir="$HOME/.extract_config"
declare -r config_file="$config_dir/extract.config"

declare -r video_exts=("*.avi" "*.mp4" "*.mov" "*.wmv" "*.rmvb" "*.mkv" "*.flv" "*.mpg" "*.mts" "*.m2ts" "*.vob" "*.MP4" "*.AVI" "*.MOV" "*.WMV" "*.RMVB" "*.MKV" "*.FLV" "*.MPG" "*.MTS" "*.M2TS" "*.VOB")
declare -r image_exts=("*.jpg" "*.jpeg" "*.png" "*.bmp" "*.JPG" "*.JPEG" "*.PNG" "*.BMP")

declare -r video_path_pattern="\\.(mp4|avi|mov|wmv|rmvb|mpg|mkv|flv|mts|vob|m2ts)$"
declare -r image_path_pattern="\\.(jpg|png|jpeg|bmp)$"

init(){
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
    fi

    # environment variable
    if [[ -f "$config_file" ]]; then
        while read -r line; do
            case $line in
                exclude=*) 
                    exclude_file="${line//exclude=/}"
                    declare -r exclude_file
                    ;;
                video_album_store=*) 
                    video_album_dir="${line//video_album_store=/}"
                    declare -r video_album_dir 
                    ;;
                video_store=*) 
                    video_save_dir="${line//video_store=/}"
                    declare -r video_save_dir
                    ;;
                image_store=*) 
                    image_save_dir="${line//image_store=/}"
                    declare -r image_save_dir
                    ;;
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
    local file_name
    local file_ext

    file_ext="${1##*.}"
    file_name="${1%.*}"
    file_name=$(echo "$file_name" | sed 's/\\M/*/g;s/ /*/g;s/(/*/g;s/)/*/g')
    echo "$file_name.$file_ext"
}

# $1 dir path
format_save_dir() {
    local out_dir

    out_dir=$(echo "$1" | sed 's/\/*$//g')

    echo "$out_dir"
}

# $1 dir path
check_dir(){
    if [[ "$1" != "" ]]; then
        if [[ ! -d "$1" ]]; then
            mkdir -p "$1"
        fi
        echo "0"
    else
        echo "1"
    fi
}

# $1 the prompt message
get_dir() {
    local dir_path
    local prompt_msg

    if [[ "$1" != "" ]]; then
        prompt_msg="$1"
    else
        prompt_msg="please give a new path"
    fi

    while [[ ! -d "$dir_path" ]]; do
        IFS=$'\n' read -er -p "$prompt_msg: " dir_path

        if [[ $(check_dir "$dir_path") -eq 0 ]]; then
            break;
        fi
    done

    echo "$dir_path"
}

# return the save path
# $1 max count [option]
check_store(){
    local cur_dir   
    local max_count

    if [[ "$2" -gt 0 ]]; then
        max_count=$(( $2 ))
    else
        max_count=55
    fi

    cur_dir="$1"

    if [[ $(check_dir "$cur_dir") -ne 0 ]]; then
        cur_dir="$(get_dir)"
    fi

    while [[ $(sandbox "find \"$cur_dir\" -maxdepth 1 -printf %P\\\\n | grep -ic \"^[^\\\\.]\"") -ge $max_count ]]; do
        cur_dir="$(get_dir "The dir is full, please give a new path")"
    done

    echo "$cur_dir"
}

get_file_type() {
    local file_type_str

    file_type_str=$(file "$1")

     if [[ $(echo "$file_type_str" | grep -c -i "rar") -gt 0  ]]; then
        echo "rar"
    elif [[ $(echo "$file_type_str" | grep -c -i "7z") -gt 0  ]]; then
        echo "7z"
    elif [[ $(echo "$file_type_str" | grep -c -i "zip") -gt 0 ]]; then
        echo "zip"
    else
        echo 'unkonw file'
        exit 1
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
    local file_type

    file_type=$(get_file_type "$1")

    if [[ -f $exclude_file ]]; then
        if [[ "$file_type" == "zip" ]]; then
           excludes=" -x "$(sed ':a ; N;s/\n/ / ; t a ; ' "$exclude_file")
        elif [[ "$file_type" == 'rar' ]]; then
            excludes=" -x@\"$exclude_file\""
        elif [[ "$file_type" == '7z' ]]; then
            excludes=" -x@\"$exclude_file\""
        fi
    fi 

    if [[ "$file_type" == 'rar' ]]; then
        exec_cmd="unrar -or -p\"$2\"$excludes e \"$1\" ${exts_parrtern[*]} \"$4\""
    elif [[ "$file_type" == "zip" ]]; then
       exec_cmd="unzip -P$2 -Ocp936 -j \"$1\" ${exts_parrtern[*]} $excludes  -d \"$4\""
    elif [[ "$file_type" == '7z' ]]; then
        exec_cmd="7za -p\"$2\" -o\"$4\"$excludes e \"$1\" ${exts_parrtern[*]} -sccUTF-8 -aot -r"
    else
        echo 'unkonw file'
        return 1;
    fi
    
    sandbox "$exec_cmd"
    return $?
}

# $1 file_name
# $2 password
extract_list() {
    local exec_cmd
    local excludes
    local videoext
    local imgext
    local file_type

    videoext="${video_exts[*]}"
    videoext="${videoext//\*/\\*}"
    imgext="${image_exts[*]}"
    imgext="${imgext//\*/\\*}"

    file_type=$(get_file_type "$1")

    if [[ -f "$exclude_file" ]]; then
        if [[ "$file_type" == "zip" ]]; then
            excludes=" -x "$(sed ':a ; N;s/\n/ / ; t a ; ' "$exclude_file")
        elif [[ "$file_type" == 'rar' || "$file_type" == '7z' ]]; then
            excludes=" -x@\"$exclude_file\""
        fi
    fi 
    
    if [[ "$file_type" == 'rar' ]]; then
        exec_cmd="unrar -p\"$2\"$excludes lb \"$1\" $videoext $imgext"
    elif [[ "$file_type" == "zip" ]]; then
        exec_cmd="unzip -P$2 -Ocp936 -l \"$1\" $videoext $imgext $excludes | sed -n \"/---------/,\\\$p\" | sed \"/---------/d;\\\$d\" | while read -r _ _ _ c4; do echo \"\$c4\"; done"
    elif [[ "$file_type" == '7z' ]]; then
        exec_cmd="7za -slt -p\"$2\"$excludes l \"$1\" $videoext $imgext -r -sccUTF-8 | sed -n 's/Path = //gp'"
    else
        echo 'unkonw file'
        exit 1; 
    fi
    sandbox "$exec_cmd > $list_content"
    return $?
}

get_pwd() {
    if [[ $epassword != '' ]]; then
        echo "$epassword"
    else
        echo "";
    fi
    
    return 0;
}

# $1 file_name
del_file(){
    if [[ $auto_del == false ]]; then
        return 0
    fi

    local rm_file

    rm_file="${1%.*}"
    rm_file="${rm_file//part*/part*}.${1##*.}" 
    rm_file=$(echo "$rm_file" | sed -E "s/\\(|\\)|\\[|\\]|\\s/*/g")

    read -r -p "confirm delete file: $rm_file, [y]es: " confirm

    if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
      return 0
    fi

    msg "delete file $rm_file \\n"

    for i in $rm_file
    do
        cp /dev/null "$i" 
        rm -f "$i"
    done
}
# $1 file path
# $2 file name
get_basename(){
    local file_path
    local file_name

    file_path="$1"
    file_name="$2"

    local base_name

    case $base_name_type in
        file) 
            base_name="${file_name%%.*}" 
            ;;
        tree) 
            base_name=$(dirname "$file_path" | awk -F'/' '{print $NF}')
            
            if [[ "$base_name" == '.' ]]; then
                local confirm

                read -r -p "The $file_path have not subtree, do want to give a new name [y]es or by default: " confirm

                if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
                    local new_name

                    while [[ "$new_name" == "" ]]; do
                        read -r -p "Please give a new name: " new_name
                    done

                    base_name="$new_name"
                else
                    base_name="${base_name%.*}"
                fi
            fi
            ;;
        *)
            base_name=$(basename "$file_path")
            base_name="${base_name%.*}"
            ;;
    esac

    echo "${base_name// /_}"
}

# $1 file_name
# $2 password
extract_pic(){
    local pic_count
    local file_path
    local dir_name
    local save_path
    local index
    local parttern

    msg "Image checking, pleas wait for a moment !\\n"
    pic_count=$(sandbox "grep -c -i -E \"$image_path_pattern\" \"$list_content\"")

    if [[ $pic_count -gt 10 ]]; then
        index=1
        
        while read -r line; do
            if [[ index -eq 1 ]]; then
                file_path="$line"
            fi

            msg "Found -> $line"

            index=$(( index + 1 ))
        done <<< "$(grep -i -E "$image_path_pattern" "$list_content" | head -n 20)"

        dir_name=$(get_basename "$file_path" "$1")

        if [[ $assing_dir != '' ]]; then
            save_path="$assing_dir/$dir_name"
        elif [[ -d "$image_save_dir"  ]]; then
            local img_save_path

            img_save_path=$(check_store "$image_save_dir" 30)

            save_path="$img_save_path/$dir_name"
        else 
            save_path="$(pwd)/$dir_name"
        fi

        msg --warn "\\nConfim the save path $save_path \\n"

        read -r -p "[y]es or [n]ew or [e]xit, file partten [option]:" confirm parttern

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

        if [[ "$parttern" != "" ]]; then
            extract_file "$1" "$2" "$parttern" "$save_path" 
        else
            extract_file "$1" "$2" "${image_exts[*]}" "$save_path" 
        fi
        del_file "$1"
    else
        msg --prompt "there are no more pictures ! \\n"
        del_file "$1"
    fi
}
# $1 filter name
exclude_filter() {
    if [[ ${#var_exclude[*]} -eq 0 ]]; then
        echo 0
        return 0
    fi

    for i in "${var_exclude[@]}"; do
        if [[ "$1" == "$i" ]]; then
            echo 1
            return 0
        fi
    done

    echo 0
    return 0
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

    msg "\\n////////////////////////////////////////////////\\n"

    extract_list "$1" "$pwd" > /dev/null

    local count

    count=$(sandbox "grep -i -c -E \"$video_path_pattern\" \"$list_content\"")

    if [[ $count -eq 0 || $only_extrac_pic == true ]]; then
        msg --prompt "No media files !\\n"
        extract_pic "$1" "$pwd"
        return 0;
    fi

    local file_path
    local index

    index=0

    while read -r line ; do
        if [[ index -eq 0  ]]; then
            file_path="$line"
        fi
        msg "Found -> $line"
    done <<< "$(grep -i -E "$video_path_pattern" "$list_content")"

    local base_name

    base_name=$(get_basename "$file_path" "$1")

    local exp_dir
    local file_name
    local extract_pattern
    local ext
    local new_file_name

    if [[ $count -gt 1 ]]; then
        if [[ -d "$assing_dir" ]]; then
            exp_dir="$(check_store "$assing_dir/$base_name")"
        else
            exp_dir="$(check_store "$video_album_dir/$base_name")"           
        fi
        
        msg --warn "\\nThere are more then one media file. Confirm save path: $exp_dir"

        read -r -p "[y]es or [n]ew or [e]xit: " confirm

        case $confirm in 
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
        if [[ -d "$assing_dir" ]]; then
            exp_dir=$(check_store "$assing_dir")
        else
            exp_dir=$(check_store "$video_save_dir")
        fi
        
        exp_dir=$(format_save_dir "$exp_dir")

        file_name=$(basename "$file_path")
        extract_pattern="*"$(format_extract_name "$file_name")
        ext=$(echo "${file_name##*.}" | tr '[:upper:]' '[:lower:]')
        # shellcheck disable=SC2001
        new_file_name="$(echo "$base_name" | sed -e "s@\\W@@g").$ext"
        
        extract_file "$1" "$pwd" "$extract_pattern" "$exp_dir"

        if [[ "$file_name" != "$new_file_name" ]]; then
            mv "${exp_dir//\\/}/${file_name}" "${exp_dir//\\/}/$new_file_name"
        fi

        msg --prompt "\\n$(file "$exp_dir/$new_file_name")"
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
        notrash) auto_del=false ;;
        pwd=*) epassword="${OPTARG//pwd=/}" ;;
        onlypic) only_extrac_pic=true ;;
        basename=*) base_name_type="${OPTARG//basename=/}" ;;
        debug) set -x ;;
        content=*) list_content="${OPTARG//content=/}" ;;
        X=*) IFS="," read -r -a var_exclude <<< "${OPTARG//X=/}" ;;
    esac
done

if [[ "$epassword" == '' && "$target" == '' ]]; then
    msg --error "Please set the target or give a password ! \\n"
    exit 1
fi

shift $(( OPTIND - 1 ))

init # initialize environment

while [[ -n "$1" ]]; do
    if [[ $(exclude_filter "${1%%.*}") -eq 0 ]]; then
        # create content file when it no special
        if [[ ! -f "$list_content" ]]; then
            list_content="/tmp/$(date +%s%N).ea"
        fi
        # start
        main "$1"
        # delete tmp content file
        if [[ -f "$list_content" ]]; then
          rm -f "$list_content"
        fi
    else
        echo -e "Exclude file $1"
    fi

    shift
done