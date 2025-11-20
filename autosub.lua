-- autosub.lua
--
-- Auto / manual subtitle downloader + loader for mpv.
--
-- Features:
--   * Uses an external CLI downloader (default: `subliminal`) to fetch subtitles.
--   * Works for local files and HTTP/HTTPS streams.
--   * Local files:
--       - Saves subs in the video folder, a subdir, or a fixed folder.
--       - Reuses existing subs if found; only downloads if none match.
--   * HTTP/HTTPS streams:
--       - Requires `stream_download_dir` in autosub.conf.
--       - Reuses existing subs that match the stream’s basename; only downloads if none.
--   * Language-aware:
--       - You specify desired languages (e.g. "en,eng,fr").
--       - Skips download in auto mode if a track in those languages already exists.
--   * Modes:
--       - auto   = run automatically on file-loaded
--       - manual = run only when triggered (keybind / script-message)
--   * Shows status messages on mpv’s OSD.

local mp      = require("mp")
local msg     = require("mp.msg")
local utils   = require("mp.utils")
local options = require("mp.options")

local o = {
    -- Comma-separated list of language codes (ISO 639-1/2, e.g. "en", "en,eng,fr").
    languages = "en",

    -- Local file behavior:
    --   "filedir" = put subs next to the video file
    --   "subdir"  = put subs in a subdirectory inside the video folder
    --   "fixed"   = always use local_fixed_dir below
    local_download_mode = "filedir",
    local_subdir        = "subs",
    local_fixed_dir     = "",

    -- Directory for subtitles when playing HTTP/HTTPS streams.
    -- Must be set by the user. If empty, script will warn and skip streams.
    stream_download_dir = "",

    -- Subtitle downloader (default: subliminal).
    -- Expected CLI:
    --   downloader download -l <lang> -d <dir> -- <video_path>
    downloader            = "subliminal",
    downloader_extra_args = "",

    -- Behavior regarding *existing subtitle tracks* in the playing file:
    --   "no"      = skip download if a subtitle in one of the desired languages exists
    --   "always"  = ignore existing tracks and still do folder-check + downloader
    download_when_subs_present = "no",

    -- Mode:
    --   "auto"   = run automatically on file-loaded
    --   "manual" = run only when triggered via keybinding / script-message
    mode = "auto",
}

-- Helper: show a message both on OSD and in the log.
local function osd(text)
    mp.osd_message(text, 3)
    msg.info(text)
end

options.read_options(o, "autosub")
o.mode = (o.mode or "auto"):lower()
if o.mode ~= "auto" and o.mode ~= "manual" then
    o.mode = "auto"
end

-- Helpers ---------------------------------------------------------------------

local function is_stream(path)
    return path and path:match("^%a+://") ~= nil
end

local function urldecode(str)
    if not str then return nil end
    return str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end):gsub("+", " ")
end

local function get_local_basename_and_dir(path)
    local dir, filename = utils.split_path(path)
    local base = filename:gsub("%.[^%.]+$", "") -- strip last extension
    return base, filename, dir
end

local function get_stream_basename(url)
    local noquery = url:gsub("%?.*$", "")
    local last    = noquery:match("([^/]+)$") or noquery
    last          = urldecode(last)
    last          = last:gsub("#.*$", "")       -- strip fragment
    local base    = last:gsub("%.[^%.]+$", "")  -- strip extension
    return base
end

local function ensure_dir(path)
    if not path or path == "" then return end
    local is_windows = package.config:sub(1,1) == "\\"
    if is_windows then
        utils.subprocess({ args = {"cmd", "/C", "mkdir", path}, cancellable = false })
    else
        utils.subprocess({ args = {"mkdir", "-p", path}, cancellable = false })
    end
end

-- Language handling -----------------------------------------------------------

local function parse_languages()
    local set = {}
    for lang in o.languages:gmatch("[^,]+") do
        lang = lang:lower():gsub("^%s+",""):gsub("%s+$","")
        if lang ~= "" then
            set[lang] = true
        end
    end
    return set
end

local desired_langs = parse_languages()

local function video_has_desired_lang_subs()
    local tracks = mp.get_property_native("track-list") or {}
    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.lang then
            local lang = t.lang:lower()
            if desired_langs[lang] then
                osd("autosub: subtitle already present (" .. lang .. ")")
                return true
            end
        end
    end
    return false
end

-- Downloader ------------------------------------------------------------------

local function build_language_args()
    local args = {}
    for lang in o.languages:gmatch("[^,]+") do
        lang = lang:gsub("^%s+",""):gsub("%s+$","")
        if lang ~= "" then
            table.insert(args, "-l")
            table.insert(args, lang)
        end
    end
    return args
end

local function split_extra_args(str)
    local t = {}
    for token in str:gmatch("%S+") do
        table.insert(t, token)
    end
    return t
end

local function run_downloader(video_path, target_dir)
    ensure_dir(target_dir)

    local args = { o.downloader, "download" }
    for _, a in ipairs(build_language_args()) do
        table.insert(args, a)
    end

    table.insert(args, "-d")
    table.insert(args, target_dir)

    if o.downloader_extra_args ~= "" then
        for _, a in ipairs(split_extra_args(o.downloader_extra_args)) do
            table.insert(args, a)
        end
    end

    table.insert(args, "--")
    table.insert(args, video_path)

    osd("autosub: downloading subtitles…")
    local res = utils.subprocess({ args = args, cancellable = false })

    if res.error or res.status ~= 0 then
        osd("autosub: subtitle download FAILED")
    else
        osd("autosub: subtitle download finished")
    end
end

-- Subtitle file selection & loading ------------------------------------------

local subtitle_extensions = { ".srt", ".ass", ".ssa", ".vtt", ".sub", ".idx" }

local function has_subtitle_ext(name)
    local lower = name:lower()
    for _, ext in ipairs(subtitle_extensions) do
        if lower:sub(-#ext) == ext then
            return true
        end
    end
    return false
end

-- Load subtitles from a directory.
-- Returns how many subs were loaded.
-- for_stream = true → stricter matching (must match basename; no language-only fallback).
local function add_subs_from_dir(dir, basename, for_stream)
    local files = utils.readdir(dir, "files") or {}
    if not files or #files == 0 then
        msg.info("autosub: no subtitle files in " .. dir)
        return 0
    end

    local selected   = {}
    local lower_base = basename and basename:lower() or nil

    -- 1) language + basename
    if lower_base and lower_base ~= "" then
        for _, f in ipairs(files) do
            if has_subtitle_ext(f) then
                local f_lower      = f:lower()
                local noext_lower  = f_lower:gsub("%.[^%.]+$", "")
                if noext_lower:find(lower_base, 1, true) then
                    for lang in o.languages:gmatch("[^,]+") do
                        lang = lang:lower():gsub("^%s+",""):gsub("%s+$","")
                        if lang ~= "" then
                            if f_lower:match("%." .. lang .. "%.[^%.]+$")
                               or f_lower:match("%." .. lang .. "$") then
                                table.insert(selected, f)
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2) basename-only (no language requirement)
    if #selected == 0 and lower_base and lower_base ~= "" then
        for _, f in ipairs(files) do
            if has_subtitle_ext(f) then
                local noext_lower = f:lower():gsub("%.[^%.]+$", "")
                if noext_lower:find(lower_base, 1, true) then
                    table.insert(selected, f)
                end
            end
        end
    end

    -- 3) language-only (ONLY for local files; never for streams)
    if not for_stream and #selected == 0 then
        for _, f in ipairs(files) do
            if has_subtitle_ext(f) then
                local f_lower = f:lower()
                for lang in o.languages:gmatch("[^,]+") do
                    lang = lang:lower():gsub("^%s+",""):gsub("%s+$","")
                    if lang ~= "" then
                        if f_lower:match("%." .. lang .. "%.[^%.]+$")
                           or f_lower:match("%." .. lang .. "$") then
                            table.insert(selected, f)
                            break
                        end
                    end
                end
            end
        end
    end

    if #selected == 0 then
        osd("autosub: no matching subtitles in " .. dir)
        return 0
    end

    local added = 0
    for _, f in ipairs(selected) do
        local full = utils.join_path(dir, f)
        osd("autosub: loading subtitle: " .. f)
        mp.commandv("sub-add", full, "select")
        added = added + 1
    end

    return added
end

-- Local file handler ----------------------------------------------------------

local function download_for_local(path)
    local basename, _, filedir = get_local_basename_and_dir(path)

    local target_dir
    if o.local_download_mode == "fixed" and o.local_fixed_dir ~= "" then
        target_dir = o.local_fixed_dir
    elseif o.local_download_mode == "subdir" then
        target_dir = utils.join_path(filedir, o.local_subdir)
    else
        target_dir = filedir
    end

    ensure_dir(target_dir)

    -- 1) Always try to use existing subs first (both auto & manual)
    local existing = add_subs_from_dir(target_dir, basename, false)
    if existing > 0 then
        osd("autosub: using existing local subtitles (" .. existing .. "); no download")
        return
    end

    -- 2) If none, download and then load
    osd("autosub: downloading subtitles to local folder…")
    run_downloader(path, target_dir)
    add_subs_from_dir(target_dir, basename, false)
end

-- Stream handler --------------------------------------------------------------

local function download_for_stream(url)
    if not o.stream_download_dir or o.stream_download_dir == "" then
        osd("autosub: stream_download_dir is not set; skipping stream subtitles")
        return
    end

    local basename = get_stream_basename(url)
    local dir      = o.stream_download_dir

    ensure_dir(dir)

    -- 1) Try existing subs first (both auto & manual)
    local existing = add_subs_from_dir(dir, basename, true)
    if existing > 0 then
        osd("autosub: using existing stream subtitles (" .. existing .. "); no download")
        return
    end

    -- 2) If none, download and then load
    osd("autosub: downloading subtitles for stream…")

    local dummy_path = utils.join_path(dir, basename .. ".dummy.mkv")
    local f = io.open(dummy_path, "w")
    if f then f:close() end

    run_downloader(dummy_path, dir)
    os.remove(dummy_path)

    add_subs_from_dir(dir, basename, true)
end

-- Core handler ----------------------------------------------------------------

local function handle_subs(manual)
    local path = mp.get_property("path")
    if not path then
        osd("autosub: no path, cannot handle subtitles")
        return
    end

    -- In auto mode, respect download_when_subs_present.
    -- In manual mode, we always run folder check even if embedded subs exist.
    if not manual and o.download_when_subs_present ~= "always" then
        if video_has_desired_lang_subs() then
            return
        end
    end

    if is_stream(path) then
        download_for_stream(path)
    else
        download_for_local(path)
    end
end

-- Auto mode hook --------------------------------------------------------------

local function on_file_loaded()
    if o.mode == "auto" then
        handle_subs(false)
    end
end

mp.register_event("file-loaded", on_file_loaded)

-- Manual trigger: script-binding + script-message -----------------------------

local function manual_trigger()
    handle_subs(true)
end

-- script-binding: autosub/download (for input.conf)
mp.add_key_binding(nil, "download", manual_trigger)

-- script-message: autosub-download
mp.register_script_message("autosub-download", manual_trigger)
