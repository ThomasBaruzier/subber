#!/bin/bash

# This script fetches subtitles for a movie file and burns them into the video file.
# It also fetches the movie title by parsing the filename and querying the IMDb API.
# The subtitles are downloaded from the OpenSubtitles API and cleaned up.
# The cleaned subtitles are then burnt into the video file using ffmpeg.

main() {
  file="$1"
  target="$2"

  echo
  prepare "$1"
  fetch_title
  fetch_subs
  burn_subs
  echo
}

prepare() {
  if [[ "$1" = '-h' || "$1" == '--help' ]]; then
    echo "Usage: $0 [input] {output}"
    echo
    echo "  - If the output is a file, the result will be saved at <output>"
    echo "  - If the output is a directory, the result will be saved at <output dir>/<true title>.<ext>"
    echo "  - If no output is provided, the result will be saved at <input dir>/<true title>.<ext>"
    echo "    (ffmpeg will warn before overwritting anything)"
    echo
    exit
  fi

  for prog in tcc jq curl ffmpeg; do
    if ! command -v "$prog" &> /dev/null; then
      echo -e "\e[31mERROR: '$prog' is not installed. Please install it and try again.\e[0m\n"
      exit
    fi
  done

  [ -z "$file" ] && read -p "> File to target: "
  [ ! -f "$file" ] && echo -e "\e[31mERROR : File not found\e[0m\n" && exit
  rm -rf .temp/* && mkdir -p .temp
  basename="${file##*/}" && basename="${basename%.*}"
  title="${basename//./ }"
  echo -e "> File : \e[36m$title\e[0m"
}

fetch_title() {
  # Replace any superscript digits with regular digits in the movie title
  powers=(⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹)
  for ((i=0; i < 10; i++)); do
    title="${title//${powers[i]}/$i}"
  done

  # If the title contains a year, parse the year and remove any additional information from the title
  # Otherwise, the entire title is used to query the IMDb API
  title_tokens=($title)
  if [[ "$title" =~ '19'[5-9][0-9]|'20'[0-2][0-9] ]]; then
    while (("${#title_tokens[@]}" > 0)); do
      [[ "${title_tokens[${#title_tokens[@]}-1]}" =~ '19'[5-9][0-9]|'20'[0-2][0-9] ]] && break
      unset title_tokens["${#title_tokens[@]}"-1]
    done
    date=" ${title_tokens[-1]//[^0-9]/}"
    unset title_tokens["${#title_tokens[@]}"-1]
    title_fallback="${title_tokens[@]}"
  else
    title_fallback="$title"
  fi

  # Query the IMDb API to get the true movie title and release year
  unset new_title fix_title
  while [[ -z "$new_title" || "$new_title" = "null" ]]; do
    title="${title_tokens[@]}${date}"
    title="$(jq -sRr @uri <<< $title)"
    title="${title//%0A/}"
    request=$(curl -s "https://v3.sg.media-imdb.com/suggestion/x/${title}.json" | jq ' .d[] | select(.qid | test("short|video";"i") | not)' 2>/dev/null)
    year=$(grep -Po '"y": \K[0-9]+' <<< "$request" | head -n 1)
    new_title=$(grep -Po '"l": "\K[^\"]+' <<< "$request" | head -n 1)
    id=$(grep -Po '"id": "tt0*\K[0-9]+' <<< "$request" | head -n 1)
    if [[ -z "$title_tokens" && ("$new_title" = "null" || -z "$new_title") ]]; then
      new_title="${title_fallback}${date}"
    elif [[ "$new_title" != "null" && -n "$new_title" ]]; then
      new_title="${new_title} (${year})"
    else
      unset title_tokens["${#title_tokens[@]}"-1]
    fi
  done

  # Print the true movie title for the user
  echo -e "> Title : \e[36m$new_title\e[0m"
  title="$new_title"
}

fetch_subs() {
  # Set the language codes for the subtitles to search for
  first_lang='en'
  second_lang='fr'

  # Search for subtitles for the input file on the OpenSubtitles API
  echo -e '\n\e[34mSearching subtitles...\e[0m'
  [ -z "$first_lang" ] && echo -e "\e[31mError : No first lanaguage\e[0m" && exit
  [ -n "$first_lang" ] && languages="languages=$first_lang"
  [ -n "$second_lang" ] && languages+=",$second_lang"

  # Calculate the hash of the input file to use in the OpenSubtitles API request (please excuse me for this eye-bleeding approach)
  hash=$(tcc -run - <<< "#include<stdio.h>void main(){unsigned long h=0,b[8192*2];FILE*file=fopen(\"$file\",\"r\");fread(b,8192,8,file);fseek(file,-65536,SEEK_END);fread(&b[8192],8192,8,file);for(int i=0;i<8192*2;i++)h+=b[i];h+=ftell(file);printf(\"%lx\",h);}")

  # Send the API request and filter the response for valid subtitles
  request=$(curl -s "https://api.opensubtitles.com/api/v1/subtitles?${languages}&moviehash=${hash}" -H "Api-Key: $OPENSUBTITLES_API_KEY")
  request=$(echo "$request" | jq -r '.data[] | select(.attributes.subtitle_id != null) | select(.attributes.language == "'"$first_lang"'" or .attributes.language == "'"$second_lang"'") | select(.attributes.ai_translated == false) | select(.attributes.machine_translated == false)')
  if [ -z "$request" ]; then
    request=$(curl -s "https://api.opensubtitles.com/api/v1/subtitles?imdb_id=${id}" -H "Api-Key: $OPENSUBTITLES_API_KEY")
    request=$(echo "$request" | jq -r '.data[] | select(.attributes.subtitle_id != null) | select(.attributes.language == "'"$first_lang"'" or .attributes.language == "'"$second_lang"'") | select(.attributes.ai_translated == false) | select(.attributes.machine_translated == false)')
    [ -z "$request" ] && echo -e "\e[31mFound no subtitles\e[0m" && exit
  fi

  # Filter the subtitles by matching the movie hash, filename, and IMDb ID
  # Could be refactored in the future
  old_request="$request"
  request=$(echo "$request" | jq -r "select(.attributes.language == \"$first_lang\")")
  if [ -z "$request" ]; then
    request="$old_request"
    request=$(echo "$request" | jq -r "select(.attributes.language == \"$second_lang\")")
    old_request="$request"
    echo -e "\e[33mFound only second language ($second_lang) subtitles\e[0m"
  else
    old_request="$request"
    echo -e "\e[32mFound first language ($first_lang) subtitles\e[0m"
  fi
  request=$(echo "$request" | jq -r 'select(.attributes.moviehash_match == true)')
  if [ -z "$request" ]; then
    request="$old_request"
    echo -e "\e[33mFound only non matching movie hash subtitles\e[0m"
  else
    old_request="$request"
    echo -e "\e[32mFound matching movie hash subtitles\e[0m"
  fi
  request=$(echo "$request" | jq -r 'select(.attributes.release == "'"$basename"'")')
  if [ -z "$request" ]; then
    request="$old_request"
    echo -e "\e[33mFound only non matching filename subtitles\e[0m"
  else
    old_request="$request"
    echo -e "\e[32mFound matching filename subtitles\e[0m"
  fi
  request=$(echo "$request" | jq -r "select(.attributes.feature_details.imdb_id == $id)")
  if [ -z "$request" ]; then
    request="$old_request"
    echo -e "\e[33mFound onoy non matching IMDB ID subtitles\e[0m"
  else
    old_request="$request"
    echo -e "\e[32mFound matching IMDB ID subtitles\e[0m"
  fi
  request=$(echo "$request" | jq -r "select(.attributes.hearing_impaired == false)")
  if [ -z "$request" ]; then
    request="$old_request"
    echo -e "\e[33mFound only non text-only subtitles\e[0m"
  else
    echo -e "\e[32mFound text-only subtitles\e[0m"
  fi

  # Download the best matching subtitle and clean it up (sorry for the eye-bleeding approach again)
  request=$(sed 's:^}:},:g' <<< "$request")
  request=$(jq <<< "[${request::-1}]")
  sub_id=$(jq -r 'max_by(.attributes.download_count).attributes.files[0].file_id' <<< "$request")
  sub_lang=$(jq -r 'max_by(.attributes.download_count).attributes.language' <<< "$request")
  request=$(curl -s --request POST "https://api.opensubtitles.com/api/v1/download?file_id=$sub_id" -H "Api-key: $OPENSUBTITLES_API_KEY")
  link=$(jq -r .link <<< "$request")
  [ -z "$link" ] && echo -e "\e[31mBad API key or request limit reached\e[0m" && exit
  curl -s "$link" > ".temp/$title.srt"
  sub=$(curl -s "$link" | grep -v "^00:00:00" | grep -v -E "^(Subtitles|Edited|Captioned) by" | grep -v "SDI Media Group" | grep "[a-zA-Z0-9]" | grep -vE '\.(com|org|fr|es|be|co|uk|us|pw|io|ai|net)' | grep -vE 'www|http' \
  | grep -v -E "^\(.*\)$|^\[.*\]$" | sed -n '/[^\x00-\x7F\u0080-\u00FF\u0100-\u017F\u0180-\u024F\u0250-\u02AF\u0300-\u036FΔωστλβμ£€ηδρπαθε—–−‐―’ʼ“”″ʻʻ′‘ˈ ±асο∼≈½⅓…․∗ø]/!p' \
  | sed -E -z 's:(\n|^)[0-9]+(\n[0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3} --> [0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3}):\n\2:g' | sed -E -z 's:\n([^\n]+\n){10,}::g' \
  | sed -E -z 's:([0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3} --> [0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3}\n+)+([0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3} --> [0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3}):\2:g' \
  | sed -E -z 's:\n[0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3} --> [0-9]{2}\:[0-9]{2}\:[0-9]{2},[0-9]{3}\n*$::g')

  # Filter the downloaded subtitle to remove unwanted lines and fix formatting issues
  count=1
  start='false'
  while read -r line; do
    if [[ "$line" =~ ^[0-9][0-9]':'[0-9][0-9]':'[0-9][0-9]','[0-9][0-9][0-9]' --> '[0-9][0-9]':'[0-9][0-9]':'[0-9][0-9]','[0-9][0-9][0-9]$ ]]; then
      filtered+=$'\n'"${count}"$'\n'"${line}"
      start=true
      ((count++))
    elif [ "$start" = 'true' ]; then
      filtered+=$'\n'"${line}"
    fi
  done <<< "$sub"

  sub=$(sed -E -z 's:^\n*::g' <<< "$filtered" | sed -E -z 's:\n*$:\n:g')
  sub_file=".temp/${title}.fix.srt"
  echo "$sub" > "$sub_file"
  echo -e '\e[34mSubtitles downloaded and cleaned !\e[0m'
}

burn_subs() {
  # Determine the output file path based on the user-provided target or the default directory
  if [ -d "$target" ]; then
    target="$target/$new_title.${file##*.}"
  elif [ -n "$target" ]; then
    target="$target"
  else
    target="${file%/*}/$new_title.${file##*.}"
  fi

  # Burn the cleaned subtitles into the video file using ffmpeg
  [ "$sub_lang" = 'en' ] && sub_lang=eng
  [ "${file##*.}" = "mkv" ] && sub_codec='srt' || sub_codec='mov_text'
  echo && ffmpeg -loglevel warning -hide_banner -stats -i "$file" -i "$sub_file" -c:v copy -c:a copy -c:s "$sub_codec" -sub_charenc UTF-8 -metadata:s:s:0 language="$sub_lang" "$target" && \
  echo -e "\e[34mSubtitles successfully burnt! (Saved at : $target)\e[0m" || echo -e "Error ! ($file)\e[0m"
}

main "$@"
