# mpv-autosub

An mpv Lua script that automatically downloads and loads subtitles for both local files and HTTP/HTTPS streams using an external tool such as `subliminal`.

## Features

- Local files
  - Searches for existing subtitles in:
    - the same folder as the video,
    - a subdirectory inside the video folder,
    - or a fixed directory that you configure.
  - If suitable subtitles already exist in that folder, they are loaded.
  - If not, the script downloads new ones using your chosen downloader.

- HTTP/HTTPS streams
  - Derives a stream name (basename) from the URL.
  - Uses a user-configured directory (`stream_download_dir`) to store subtitles.
  - If `stream_download_dir` is not set, it shows a warning and skips handling stream subtitles.
  - For each stream, only subtitles whose filenames match the derived basename (and optionally language) are considered.
  - If matching subtitles exist, they are reused; otherwise, new subtitles are downloaded.

- Language-aware
  - You specify preferred subtitle languages (for example: `en`, or `en,eng`).
  - The script:
    - Checks if the file already contains a subtitle track in one of those languages.
    - If so, and `download_when_subs_present=no`, it will not attempt to download more subtitles.

- Smart matching and no “load everything”
  - The script never blindly loads all subtitle files from a directory.
  - It only loads subtitles if they match:
    - the desired language(s) and/or
    - the basename of the current video or stream.
  - If nothing matches, it does not load any subtitles from that directory.

- On-screen display (OSD)
  - The script shows status messages such as:
    - `autosub: downloading subtitles…`
    - `autosub: subtitle download finished`
    - `autosub: loading subtitle: Some.File.en.srt`
    - `autosub: stream_download_dir is not set; skipping stream subtitles`


## Requirements

- mpv with Lua enabled.
- A subtitle downloader CLI tool. By default this script is configured for `subliminal`, which must be available in your system `PATH`.

The expected CLI format is roughly:

    subliminal download -l <lang> -d <dir> -- <video_path>

If you use a different downloader, adapt the `downloader` and `downloader_extra_args` settings in the config to match.


## Installation

1. Put the script in mpv's scripts directory.

Linux/macOS:

    ~/.config/mpv/scripts/autosub.lua

Windows:

    %APPDATA%\mpv\scripts\autosub.lua

For example:

    C:\Users\YourName\AppData\Roaming\mpv\scripts\autosub.lua

2. Put the config file in mpv's script-opts directory.

Linux/macOS:

    ~/.config/mpv/script-opts/autosub.conf

Windows:

    %APPDATA%\mpv\script-opts\autosub.conf

3. Make sure your downloader works.

From a terminal, verify:

    subliminal --help

If it fails, fix your subliminal installation or PATH before using the script.


## Configuration

Configuration is done through `autosub.conf` in the `script-opts` directory.

Example:

    # Languages you want (comma-separated).
    languages=en

    # Local file behavior:
    #   filedir = put subs next to the video
    #   subdir  = put subs in a subdirectory inside the video folder
    #   fixed   = always use local_fixed_dir for local files
    local_download_mode=subdir
    local_subdir=subs

    # If using a fixed directory for local files, you can set:
    # local_download_mode=fixed
    # local_fixed_dir=/home/you/Downloads/subtitles
    # local_fixed_dir=C:\Users\You\Downloads\subtitles
    local_fixed_dir=

    # Directory for HTTP/HTTPS stream subtitles.
    # This MUST be set for stream subtitle support to work.
    # If left empty, the script will show a warning and skip subtitles for streams.
    #
    # Examples:
    #   stream_download_dir=/home/you/.local/share/mpv/stream-subs
    #   stream_download_dir=C:\Users\You\AppData\Local\Temp\mpv-autosub
    stream_download_dir=

    # Subtitle downloader (CLI tool).
    downloader=subliminal

    # Extra arguments for the downloader (optional).
    # Example: prefer OpenSubtitles only:
    # downloader_extra_args=--provider opensubtitles
    downloader_extra_args=

    # When to download if subs already exist in the *file*:
    #   no      = skip download if a subtitle in one of the desired languages exists
    #   always  = always run folder-check + downloader, regardless of existing tracks
    download_when_subs_present=no

### Notes on paths

- Do not use quotes around paths. For example, on Windows:

  - Correct:
        stream_download_dir=C:\Users\You\stream-subs

  - Incorrect:
        stream_download_dir="C:\Users\You\stream-subs"

- On Linux/macOS use POSIX-style paths such as:

      local_fixed_dir=/home/you/Downloads/subtitles


## How It Works

### Local files

1. When mpv fires the `file-loaded` event for a local file:
   - The script checks the existing subtitle tracks in the file.
   - If a track is found with a language tag in your configured `languages` and `download_when_subs_present=no`, it does nothing.

2. If there is no suitable embedded subtitle track, it determines a target directory:
   - `filedir`: same folder as the video file.
   - `subdir`: a subfolder inside the video folder, named by `local_subdir`.
   - `fixed`: a single folder specified by `local_fixed_dir`.

3. It scans that directory for subtitle files:
   - First looks for filenames that contain the basename (filename without extension) and the configured language code (for example, `.en.srt`).
   - If none are found, it looks for files that match the basename, regardless of language.
   - If that still finds nothing, it looks for files that match the language alone (for local files only).

4. If matching subtitles are found, they are loaded and no download happens.

5. If no matching subtitles exist:
   - The script calls the downloader with the video path and target directory.
   - After downloading, it scans again and loads any subtitles that match the above rules.

### HTTP/HTTPS streams

1. The script extracts a basename from the URL, for example:

       http://10.0.0.1/.../Surf%20Girls%20Hawaii%20S01E02.mp4
       → Surf Girls Hawaii S01E02

2. It uses `stream_download_dir` as the only directory for stream subtitles.

3. If `stream_download_dir` is not set (empty), it shows:

       autosub: stream_download_dir is not set; skipping stream subtitles

   and does not attempt any download or loading for streams.

4. If the directory is set, it scans that folder for subtitle files:
   - First, files whose names contain the basename and one of the requested language codes.
   - Then, if none are found, files whose names contain the basename only.

5. If matching subtitles are found, they are loaded and the script skips downloading.

6. If no subtitles match:
   - A tiny dummy file named after the basename is created inside `stream_download_dir`.
   - The downloader is called with that dummy file path.
   - After completion, the dummy file is removed.
   - The directory is scanned again, and any subtitles that match the basename/language rules are loaded.


## Troubleshooting

- No OSD messages:
  - Ensure `autosub.lua` is in the correct mpv scripts directory.
  - Run mpv from a terminal and check for Lua errors in the console output.

- Downloader errors:
  - Confirm that your downloader runs outside mpv first, for example:

        subliminal download -l en -d /tmp -- "YourMovieFile.mkv"

  - If this fails, fix your downloader configuration (providers, credentials, PATH) first.

- Wrong or reused subtitles for streams:
  - The script only loads subtitles whose filenames contain the derived basename.
  - Make sure your subtitle filenames reflect the episode/movie name, e.g.:

        Surf.Girls.Hawaii.S01E02.en.srt

- Always force fresh downloads:
  - Set in `autosub.conf`:

        download_when_subs_present=always

  - This ignores existing embedded tracks, but the script will still reuse already-downloaded subs in the target folder if they match the basename.


## Credits

- Subtitle downloading typically powered by `subliminal` (https://github.com/Diaoul/subliminal).
- mpv Lua API documentation: https://mpv.io/manual/stable/#lua-scripting

## Support

If you run into any problems or have suggestions, please report them on the GitHub issues page.

If you like this tool, consider buying me a coffee.

<a href="https://www.buymeacoffee.com/fahim.ahmed" target="_blank">
  <img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" 
       alt="Buy Me A Coffee" 
       style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5); -webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5);" />
</a>