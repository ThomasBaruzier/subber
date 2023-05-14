# Subber : Accurately fetching movie titles and subtitles before seamlessly burning them.

Subber is a Bash script designed to simplify the process of embedding subtitles into a movie file. It works by first extracting the movie title from the filename and then using the IMDb API to obtain additional information that will help find the correct subtitles. Subber then downloads the appropriate subtitles from the OpenSubtitles API and clean them. Finally, it uses ffmpeg to seamlessly burn the cleaned subtitles into the video file.

## Features

### Advanced movie name detection

- The script will try to extract a valid year and will use the previous tokens as the movie title to search for on IMDb.
- Superscript digits are transformed to regular digits to ensure accurate title parsing.
- If no results is found, the script will simplify the search until a movie title is found (could lead to inacurracy, though it never happened to me)

### Advanced subtitle fecthing

- The script will extract as many parameters as possible to improve accuracy. This include the file name, year, true title, the IMDb id and the movie hash.
- It will first try to find a movie with the exact hash match and the target languages. If nothing comes up, it will try again with the other parameters.
- Then, the script will chose the subtitle to use by filtering them from the strictest to the easiest filters to ensure that the best entry is selected.

### Subtitle cleaning

- After that the subtitle is downloaded, lines with ads, links, sounds, descriptions, foreign languages are removed.
- To achieve this, the code takes the raw subtitle text data, removes unwanted lines and characters, and reformats the data into a clean and standardized format. It does this using a combination of text filtering and manipulation tools, as well as a line-by-line processing approach to ensure only relevant data is included.

## Usage

To use this script, run the following command in your terminal:

```bash
./subtitle_fetcher.sh [input] {output}
```

- If the output is a file, the result will be saved at `<output>`
- If the output is a directory, the result will be saved at `<output dir>/<true title>.<ext>`
- If no output is provided, the result will be saved at `<input dir>/<true title>.<ext>`
- If the input file is not provided, the user will be prompted to enter the file path.

## Dependencies

This script requires the following dependencies to be installed on your system:

- `curl`
- `jq`
- `tcc`
- `ffmpeg`

## Notes

- The script uses the OpenSubtitles API to download subtitles. To use this API, you will need to obtain an API key from their website.
- The script uses the IMDb API directly from the IMDB website. No API key is required (I hope this is that legal).
- The script is designed to work with movies that have a filename in the format  `<movie title> <year>.<ext>`. If your movie filenames do not follow this format, the script may not work as expected. Also, I have not tested movie shows or Anime.
- The script is designed to download and burn subtitles in English and French. If you need subtitles in other languages, you will need to modify the script accordingly.
