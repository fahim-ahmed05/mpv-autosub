# mpv-autosub

An mpv Lua script that automatically or manually downloads and loads subtitles for both local files and HTTP/HTTPS streams using an external tool such as subliminal.

## Features

- Local files
  - Searches for existing subtitles in:
    - the same folder as the video,
    - a subdirectory inside the video folder,
    - or a fixed directory that you configure.
  - Always tries to reuse existing subtitles first.
  - Only downloads new subtitles if none are found in the target folder.

- HTTP/HTTPS streams
  - Derives a stream name (basename) from the URL.
  - Uses a user-configured directory (stream_download_dir) to store subtitles.
  - Always tries to reuse existing subtitles in that directory that match the stream basename.
  - Only downloads new subtitles if none are found.
  - If stream_download_dir is not set, it shows a warning and skips stream subtitles.

- Language-aware
  - You specify preferred subtitle languages (for example: en,eng,fr).
  - In auto mode:
    - If the file already contains an embedded subtitle track in one of those languages and download_when_subs_present=no, it does nothing.
  - In manual mode:
    - Embedded tracks are ignored; manual trigger means “check folder and possibly download” regardless of what is embedded.

- No “load everything”
  - The script never blindly loads every subtitle file in a directory.
  - It only loads subtitles whose filenames match:
    - the video/stream basename and/or
    - the configured language codes.

- Modes
  - auto:
    - Automatically runs on every file-loaded event.
  - manual:
    - Does nothing automatically; you trigger it with a keybinding or script-message.

- Manual trigger
  - Exposes both:
    - a script-binding: autosub/download
    - a script-message: autosub-download
  - You can bind any key in input.conf to trigger subtitle loading/downloading for the current file.

- OSD feedback
  - Shows messages such as:
    - autosub: subtitle already present (en)
    - autosub: using existing local subtitles (1); no download
    - autosub: downloading subtitles…
    - autosub: subtitle download finished
    - autosub: no matching subtitles in C:\Users\You\Subs
    - autosub: stream_download_dir is not set; skipping stream subtitles

## Requirements

- mpv with Lua enabled.
- A subtitle downloader CLI tool. By default this script is configured for subliminal, which must be available in your system PATH.

Expected CLI format (for subliminal):

    subliminal download -l <lang> -d <dir> -- <video_path>

If you use a different downloader, adapt the downloader and downloader_extra_args options in autosub.conf.

## Installation

1. Put the script in mpv’s scripts directory.

Linux/macOS:

    ~/.config/mpv/scripts/autosub.lua

Windows:

    %APPDATA%\mpv\scripts\autosub.lua

For example:

    C:\Users\YourName\AppData\Roaming\mpv\scripts\autosub.lua

2. Put the config file in mpv’s script-opts directory.

Linux/macOS:

    ~/.config/mpv/script-opts/autosub.conf

Windows:

    %APPDATA%\mpv\script-opts\autosub.conf

3. Make sure your downloader works.

From a terminal:

    subliminal --help

If that fails, fix your downloader installation and PATH first.

## Configuration

Configuration is done through autosub.conf in the script-opts directory.

Example autosub.conf:

    # Languages you want (comma-separated).
    # You can list multiple, in order of priority.
    languages=en,eng

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
    # If left empty, the script will show a warning and skip stream subtitles.
    #
    # Examples:
    #   stream_download_dir=/home/you/.local/share/mpv/stream-subs
    #   stream_download_dir=C:\Users\You\stream-subs
    stream_download_dir=C:\Users\Fahim\Trash\Subs

    # Subtitle downloader (CLI tool).
    downloader=subliminal

    # Extra arguments for the downloader (optional).
    # Example: prefer OpenSubtitles only:
    # downloader_extra_args=--provider opensubtitles
    downloader_extra_args=

    # When to download if subs already exist in the file:
    #   no      = skip download if a subtitle in one of the desired languages exists (auto mode)
    #   always  = always perform folder check + downloader, regardless of existing tracks
    download_when_subs_present=no

    # Mode:
    #   auto   = automatically run on file-loaded
    #   manual = only run when triggered via keybinding or script-message
    mode=auto

### Notes on paths

- Do not use quotes around paths. For example, on Windows:

  Correct:

      stream_download_dir=C:\Users\You\stream-subs

  Incorrect:

      stream_download_dir="C:\Users\You\stream-subs"

- On Linux/macOS use POSIX-style paths, for example:

      local_fixed_dir=/home/you/Downloads/subtitles

## Modes and Manual Trigger

### Auto mode

Mode:

    mode=auto

Behavior:

- On each file-loaded:
  - If a subtitle track in one of your desired languages already exists and download_when_subs_present=no:
    - The script does nothing.
  - Otherwise:
    - For local files:
      - Tries to load existing subs from the configured local directory.
      - If none are found, downloads new subs and loads them.
    - For streams:
      - Tries to load existing subs from stream_download_dir.
      - If none are found, downloads new subs and loads them.

### Manual mode

Mode:

    mode=manual

Behavior:

- The file-loaded event does nothing automatic for subtitles.
- You trigger the script manually via a keybinding or script-message.
- Manual trigger behavior:
  - For local files:
    - Tries to load existing subs from the local directory.
    - Only if none are found does it download and then load.
  - For streams:
    - Tries to load existing subs from stream_download_dir.
    - Only if none are found does it download and then load.
- Embedded subtitle tracks do not prevent the script from running in manual mode.

The script exposes:

- script-binding name: autosub/download
- script-message name: autosub-download

Example input.conf bindings:

Use Ctrl+s to trigger download/load:

    Ctrl+s script-binding autosub/download

Or using the script-message directly:

    Ctrl+s script-message autosub-download

You can change the key (Ctrl+s, Alt+s, etc.) however you like; just keep the binding target the same.

## How It Works

### Local files

1. Trigger (auto or manual) calls into the core handler.
2. In auto mode, if download_when_subs_present=no:
   - The script checks the existing subtitle tracks in the file.
   - If any track has a language that matches your configured languages, it exits without touching external subs.
3. It determines the target directory:
   - filedir: same folder as the video.
   - subdir: a subfolder inside the video folder, named by local_subdir.
   - fixed: the directory given in local_fixed_dir.
4. It looks for subtitle files in that directory:
   - First: filenames containing both the video basename and a configured language code.
   - Then: filenames containing the video basename only.
   - Then (local files only): filenames containing a configured language code only.
5. If any match is found:
   - They are loaded and no download is done (both in auto and manual modes).
6. If no matching subtitles are found:
   - The downloader is called to fetch subtitles into the target directory.
   - The directory is scanned again, and matching new subtitles are loaded.

### HTTP/HTTPS streams

1. The script extracts a basename from the URL:

       http://10.0.0.1/.../Surf%20Girls%20Hawaii%20S01E02.mp4
       → Surf Girls Hawaii S01E02

2. It uses stream_download_dir as the directory for stream subtitles.
3. If stream_download_dir is empty:
   - Shows on OSD:
       autosub: stream_download_dir is not set; skipping stream subtitles
   - No downloads or loads are attempted.
4. If stream_download_dir is set:
   - The folder is scanned for subtitle files:
     - First: filenames that contain both the basename and a language code.
     - Then: filenames that contain the basename only.
   - If any match is found:
     - They are loaded and no download is done (both auto and manual).
5. If no subtitles are found for that stream:
   - A small dummy file named after the basename is created inside stream_download_dir.
   - The downloader is called with the dummy file path.
   - The dummy file is deleted.
   - The folder is scanned again and any matching subtitles are loaded.

## Troubleshooting

- No OSD messages:
  - Ensure autosub.lua is in the correct mpv scripts directory.
  - Run mpv from a terminal to see any Lua errors.

- Subtitles always download even when embedded ones exist:
  - Make sure languages in autosub.conf include all codes you expect (for example en,eng).
  - Ensure download_when_subs_present=no.

- Manual mode downloading when subs exist in the folder:
  - By design, manual mode will not download if subs matching basename/language are already present in the folder; it should only load them.
  - If you see a download, check that filenames really contain the basename or language code as expected.


## Credits

- Subtitle downloading powered by [subliminal](https://github.com/Diaoul/subliminal).
- [mpv Lua API documentation](https://mpv.io/manual/stable/#lua-scripting).

## Support

If you run into any problems or have suggestions, please report them on the GitHub issues page.

If this script helped you, consider buying me a coffee.

<a href="https://www.buymeacoffee.com/fahim.ahmed" target="_blank">
  <img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" 
       alt="Buy Me A Coffee" 
       style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5); -webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5);" />
</a>