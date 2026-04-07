#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# cb-upload.sh - CrnaBerza torrent uploader za Linux
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ─── Boje za output ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# ─── Konfiguracija ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Default vrednosti
WORK_DIR="$HOME/cb-uploader/work"
DOWNLOAD_PATH="$HOME/Downloads/torrents"
ANNOUNCE_URL="http://www.crnaberza.com/announce"
BASE_URL="https://www.crnaberza.com"
API_KEY=""
TMDB_API_KEY=""
SCREENSHOT_COUNT=10
ANONYMOUS=false

# ─── Pomoćne funkcije ─────────────────────────────────────────────────────────

log() {
    local color=$1
    local msg=$2
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${color}[$timestamp] $msg${NC}" >&2
}

log_info()    { log "$CYAN" "$1"; }
log_success() { log "$GREEN" "$1"; }
log_warning() { log "$YELLOW" "$1"; }
log_error()   { log "$RED" "$1"; }
log_gray()    { log "$GRAY" "$1"; }

check_dependencies() {
    local missing=()
    
    command -v mktorrent &>/dev/null || missing+=("mktorrent")
    command -v ffmpeg &>/dev/null || missing+=("ffmpeg")
    command -v ffprobe &>/dev/null || missing+=("ffprobe")
    command -v mediainfo &>/dev/null || missing+=("mediainfo")
    command -v jq &>/dev/null || missing+=("jq")
    command -v curl &>/dev/null || missing+=("curl")
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Nedostaju programi: ${missing[*]}"
        echo ""
        echo "Instaliraj sa:"
        echo "  sudo apt install mktorrent ffmpeg mediainfo jq curl bc"
        exit 1
    fi
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        WORK_DIR=$(jq -r '.work_dir // empty' "$CONFIG_FILE" 2>/dev/null) || WORK_DIR="$HOME/cb-uploader/work"
        DOWNLOAD_PATH=$(jq -r '.download_path // empty' "$CONFIG_FILE" 2>/dev/null) || DOWNLOAD_PATH="$HOME/Downloads/torrents"
        ANNOUNCE_URL=$(jq -r '.announce_url // empty' "$CONFIG_FILE" 2>/dev/null) || ANNOUNCE_URL="http://www.crnaberza.com/announce"
        BASE_URL=$(jq -r '.base_url // empty' "$CONFIG_FILE" 2>/dev/null) || BASE_URL="https://www.crnaberza.com"
        API_KEY=$(jq -r '.api_key // empty' "$CONFIG_FILE" 2>/dev/null) || API_KEY=""
        TMDB_API_KEY=$(jq -r '.tmdb_api_key // empty' "$CONFIG_FILE" 2>/dev/null) || TMDB_API_KEY=""
    fi
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
{
    "work_dir": "$WORK_DIR",
    "download_path": "$DOWNLOAD_PATH",
    "announce_url": "$ANNOUNCE_URL",
    "base_url": "$BASE_URL",
    "api_key": "$API_KEY",
    "tmdb_api_key": "$TMDB_API_KEY"
}
EOF
    log_success "Konfiguracija sačuvana u $CONFIG_FILE"
}

usage() {
    cat << EOF
Upotreba: $0 [opcije] <putanja>

CrnaBerza Torrent Uploader za Linux

Opcije:
  -n, --name NAME        Naziv torenta (default: ime fajla/foldera)
  -s, --screenshots N    Broj screenshot-ova (default: 10)
  -a, --anonymous        Anonimni upload
  -c, --config           Pokreni config wizard
  -h, --help             Prikaži pomoć

Primeri:
  $0 /path/to/movie.mkv
  $0 -n "Neki Film 2024" -s 5 /path/to/folder
  $0 --anonymous /path/to/video.mp4
  $0 --config

Potrebni programi:
  mktorrent, ffmpeg, ffprobe, mediainfo, jq, curl, bc

EOF
}

config_wizard() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  CrnaBerza Uploader - Konfiguracija"
    echo "═══════════════════════════════════════════"
    echo ""
    
    read -p "Radni folder [$WORK_DIR]: " input
    [ -n "$input" ] && WORK_DIR="$input"
    
    read -p "Download folder [$DOWNLOAD_PATH]: " input
    [ -n "$input" ] && DOWNLOAD_PATH="$input"
    
    read -p "Announce URL [$ANNOUNCE_URL]: " input
    [ -n "$input" ] && ANNOUNCE_URL="$input"
    
    read -p "Base URL [$BASE_URL]: " input
    [ -n "$input" ] && BASE_URL="$input"
    
    read -p "API Key: " API_KEY
    read -p "TMDB API Key: " TMDB_API_KEY
    
    save_config
}

# ─── Glavne funkcije ──────────────────────────────────────────────────────────

find_video_file() {
    local source_path="$1"
    
    if [ -f "$source_path" ]; then
        echo "$source_path"
        return
    fi
    
    # Pronađi najveći video fajl u folderu
    find "$source_path" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m2ts" -o -iname "*.wmv" -o -iname "*.mov" \) -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

create_torrent() {
    local source_path="$1"
    local output_file="$2"
    
    log_info "═══ KORAK 1: Kreiranje torenta ═══"
    log_info "Izvor: $(basename "$source_path")"
    
    # Pokreni mktorrent sa vidljivim outputom (-t 2 ograničava threadove)
    if ! mktorrent \
        -t 2 \
        -a "$ANNOUNCE_URL" \
        -p \
        -o "$output_file" \
        "$source_path"; then
        log_error "mktorrent komanda nije uspela"
        return 1
    fi
    
    if [ -f "$output_file" ]; then
        local size=$(stat -c%s "$output_file" 2>/dev/null || echo "0")
        if [ "$size" -lt 100 ]; then
            log_error "Torent fajl je prazan ili premali ($size bytes)"
            cat "$output_file" 2>/dev/null
            return 1
        fi
        local size_h=$(du -h "$output_file" | cut -f1)
        log_success "Torent kreiran: $output_file ($size_h)"
        return 0
    else
        log_error "Kreiranje torenta nije uspelo - fajl nije kreiran"
        return 1
    fi
}

generate_screenshots() {
    local video_path="$1"
    local screenshots_dir="$2"
    local count="$3"
    
    log_info "═══ KORAK 2: Screenshot-ovi i MediaInfo ═══"
    log_info "Video: $(basename "$video_path")"
    
    # Dobij trajanje
    local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_path" 2>/dev/null)
    local resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$video_path" 2>/dev/null)
    
    # Konvertuj u integer za računanje
    local dur_int=${duration%.*}
    log_info "Trajanje: $(date -u -d @${dur_int} '+%H:%M:%S'), Rezolucija: $resolution"
    
    mkdir -p "$screenshots_dir"
    
    # Generiši screenshot-ove
    local start_time=$(echo "$duration * 0.05" | bc)
    local end_time=$(echo "$duration * 0.95" | bc)
    local interval=$(echo "($end_time - $start_time) / ($count + 1)" | bc)
    
    for i in $(seq 1 $count); do
        local timestamp=$(echo "$start_time + ($interval * $i)" | bc)
        local output_ss=$(printf "$screenshots_dir/screenshot_%02d.jpg" $i)
        
        ffmpeg -y -ss "$timestamp" -i "$video_path" -vframes 1 -q:v 2 -update 1 "$output_ss" 2>/dev/null
        
        if [ -f "$output_ss" ]; then
            local time_fmt=$(date -u -d @${timestamp%.*} '+%H:%M:%S')
            log_gray "  Screenshot $i/$count @ $time_fmt"
        fi
    done
    
    local generated=$(ls -1 "$screenshots_dir"/*.jpg 2>/dev/null | wc -l)
    log_success "Generisano $generated screenshot-ova"
}

get_mediainfo() {
    local video_path="$1"
    local output_file="$2"
    
    mediainfo "$video_path" > "$output_file"
    log_success "MediaInfo sačuvan"
}

search_imdb() {
    local search_name="$1"
    local imdb_file="$2"
    
    log_info "═══ KORAK 3: IMDB Pretraga ═══"
    
    # Očisti naziv za pretragu
    local clean_name=$(echo "$search_name" | sed -E 's/\./\ /g; s/(19|20)[0-9]{2}.*$//; s/[[:space:]]+S[0-9]+.*$//; s/^[[:space:]]+|[[:space:]]+$//g')
    
    log_info "Pretraga: $clean_name"
    
    # TMDB pretraga
    local encoded_name=$(echo "$clean_name" | jq -Rr @uri)
    local search_url="https://api.themoviedb.org/3/search/multi?api_key=${TMDB_API_KEY}&query=${encoded_name}&include_adult=false"
    
    local response=$(curl -s "$search_url")
    local result_count=$(echo "$response" | jq '.results | length')
    
    if [ "$result_count" -eq 0 ] || [ "$result_count" = "null" ]; then
        log_error "TMDB pretraga nije vratila rezultate"
        return 1
    fi
    
    # Uzmi prvi rezultat
    local media_type=$(echo "$response" | jq -r '.results[0].media_type')
    local tmdb_id=$(echo "$response" | jq -r '.results[0].id')
    local title=$(echo "$response" | jq -r '.results[0].title // .results[0].name')
    
    log_info "Pronađeno: $title ($media_type)"
    
    # Dobij IMDB ID
    local details_url="https://api.themoviedb.org/3/${media_type}/${tmdb_id}/external_ids?api_key=${TMDB_API_KEY}"
    local details=$(curl -s "$details_url")
    local imdb_id=$(echo "$details" | jq -r '.imdb_id')
    
    if [ -z "$imdb_id" ] || [ "$imdb_id" = "null" ]; then
        log_error "IMDB ID nije pronađen"
        return 1
    fi
    
    local imdb_url="https://www.imdb.com/title/${imdb_id}/"
    log_success "IMDB: $imdb_url"
    
    echo -n "$imdb_url" > "$imdb_file"
    
    # Vrati media_type i original_language za kategoriju
    local orig_lang=$(echo "$response" | jq -r '.results[0].original_language // "en"')
    echo "$media_type|$orig_lang"
}

detect_category() {
    local mediainfo_file="$1"
    local media_type="$2"
    local orig_lang="$3"
    
    # HD/SD detekcija
    local width=0
    if [ -f "$mediainfo_file" ]; then
        width=$(grep -oP 'Width\s*:\s*\K[\d\s]+' "$mediainfo_file" 2>/dev/null | tr -d ' ' | head -1)
    fi
    [ -z "$width" ] && width=0
    
    local is_hd=true
    [ "$width" -lt 1280 ] && is_hd=false
    
    # Domaće/Strano
    local is_domace=false
    case "$orig_lang" in
        sr|hr|bs|sh|cnr) is_domace=true ;;
    esac
    
    # Kategorije
    declare -A categories=(
        ["Film_HD_Domace"]=73 ["Film_HD_Strano"]=48
        ["Film_SD_Domace"]=29 ["Film_SD_Strano"]=54
        ["TV_HD_Domace"]=75   ["TV_HD_Strano"]=77
        ["TV_SD_Domace"]=30   ["TV_SD_Strano"]=34
    )
    
    local is_tv=false
    [ "$media_type" = "tv" ] && is_tv=true
    
    local cat_key=""
    if $is_tv; then
        if $is_hd; then
            cat_key=$($is_domace && echo "TV_HD_Domace" || echo "TV_HD_Strano")
        else
            cat_key=$($is_domace && echo "TV_SD_Domace" || echo "TV_SD_Strano")
        fi
    else
        if $is_hd; then
            cat_key=$($is_domace && echo "Film_HD_Domace" || echo "Film_HD_Strano")
        else
            cat_key=$($is_domace && echo "Film_SD_Domace" || echo "Film_SD_Strano")
        fi
    fi
    
    local res_str=$($is_hd && echo "HD" || echo "SD")
    local type_str=$($is_tv && echo "TV Serija" || echo "Film")
    local orig_str=$($is_domace && echo "Domaće" || echo "Strano")
    
    log_info "Rezolucija: $res_str ($width px)"
    log_info "Tip: $type_str, Poreklo: $orig_str"
    log_info "Kategorija: ${cat_key//_//} (ID: ${categories[$cat_key]})"
    
    echo "${categories[$cat_key]}"
}

detect_subtitles() {
    local mediainfo_file="$1"
    local subtitles=()
    
    if [ -f "$mediainfo_file" ]; then
        local mi_lower=$(cat "$mediainfo_file" | tr '[:upper:]' '[:lower:]')
        
        echo "$mi_lower" | grep -qE 'serbian|srpski|srp' && subtitles+=("sr")
        echo "$mi_lower" | grep -qE 'croatian|hrvatski|hrv' && subtitles+=("hr")
        echo "$mi_lower" | grep -qE 'bosnian|bosanski|bos' && subtitles+=("ba")
    fi
    
    if [ ${#subtitles[@]} -gt 0 ]; then
        log_info "Titlovi: ${subtitles[*]}"
        printf '%s\n' "${subtitles[@]}" | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

upload_torrent() {
    local torrent_file="$1"
    local torrent_name="$2"
    local imdb_url="$3"
    local category_id="$4"
    local mediainfo_file="$5"
    local screenshots_dir="$6"
    local anonymous="$7"
    
    log_info "═══ KORAK 4: Upload na CrnaBerza ═══"
    
    # JSON fajl za upload
    local json_file="$WORK_DIR/upload.json"
    local tmp_dir="$WORK_DIR/tmp"
    mkdir -p "$tmp_dir"
    
    # Base64 torrent - sačuvaj u fajl
    base64 -w0 "$torrent_file" > "$tmp_dir/torrent.b64"
    log_info "Torent učitan"
    
    # MediaInfo - escape za JSON
    local mediainfo_escaped='""'
    if [ -f "$mediainfo_file" ]; then
        jq -Rs . < "$mediainfo_file" > "$tmp_dir/mediainfo.json"
        mediainfo_escaped=$(cat "$tmp_dir/mediainfo.json")
    fi
    
    # Titlovi
    local subtitles_json=$(detect_subtitles "$mediainfo_file")
    
    # Screenshot-ovi - base64 u pojedinačne fajlove
    local ss_count=0
    for img in $(ls "$screenshots_dir"/*.jpg 2>/dev/null | sort | head -10); do
        base64 -w0 "$img" > "$tmp_dir/ss_${ss_count}.b64"
        ss_count=$((ss_count + 1))
    done
    log_info "Screenshot-ova učitano: $ss_count"
    
    # Escape naziv i IMDB
    local escaped_name=$(printf '%s' "$torrent_name" | jq -Rs .)
    local escaped_imdb=$(printf '%s' "$imdb_url" | jq -Rs .)
    
    # Default category ako nije setovana
    [ -z "$category_id" ] && category_id=48
    
    log_info "Pripremam JSON..."
    log_info "Kategorija ID: $category_id"
    
    # Gradi JSON ručno koristeći fajlove - bez newline u base64
    {
        printf '{"torrent_file":"'
        cat "$tmp_dir/torrent.b64"
        printf '","name":%s,' "$escaped_name"
        printf '"description":"Auto-generated from IMDB",'
        printf '"category":%s,' "$category_id"
        printf '"url":%s,' "$escaped_imdb"
        printf '"anonymous":%s,' "$anonymous"
        printf '"allow_comments":true,'
        printf '"mediainfo":%s,' "$mediainfo_escaped"
        printf '"subtitles":%s,' "$subtitles_json"
        printf '"screenshots":['
        
        local first=true
        for i in $(seq 0 $((ss_count - 1))); do
            $first || printf ','
            first=false
            printf '"'
            cat "$tmp_dir/ss_${i}.b64"
            printf '"'
        done
        
        printf ']}'
    } > "$json_file"
    
    # Proveri da li je JSON validan
    if ! jq empty "$json_file" 2>/dev/null; then
        log_error "Generisani JSON nije validan!"
        log_info "Prve linije JSON-a:"
        head -c 500 "$json_file" >&2
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Očisti temp fajlove
    rm -rf "$tmp_dir"
    
    local body_size=$(du -h "$json_file" | cut -f1)
    log_info "JSON veličina: $body_size"
    
    # Upload koristeći fajl
    log_warning "Upload u toku..."
    
    local response=$(curl -s -X POST \
        -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json; charset=utf-8" \
        --data-binary @"$json_file" \
        --max-time 300 \
        "$BASE_URL/wp-json/cb/v1/upload")
    
    # Očisti JSON fajl
    rm -f "$json_file"
    
    # Proveri odgovor
    local torrent_id=$(echo "$response" | jq -r '.torrent_id // empty')
    
    if [ -z "$torrent_id" ]; then
        local error=$(echo "$response" | jq -r '.message // .error // "Nepoznata greška"')
        log_error "Upload nije uspeo: $error"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
    
    local name=$(echo "$response" | jq -r '.name')
    local size=$(echo "$response" | jq -r '.size')
    local url=$(echo "$response" | jq -r '.url')
    local size_gb=$(echo "scale=2; $size / 1073741824" | bc)
    
    echo ""
    log_success "═══════════════════════════════════════════"
    log_success "USPEŠNO UPLOADOVANO!"
    log_success "═══════════════════════════════════════════"
    log_info "Torent ID: $torrent_id"
    log_info "Naziv: $name"
    log_info "Veličina: ${size_gb} GB"
    log_info "URL: $url"
    
    # Preuzmi torent sa passkey-em
    log_warning "Preuzimanje torenta sa passkey-em..."
    
    local dl_response=$(curl -s -X GET \
        -H "X-API-Key: $API_KEY" \
        "$BASE_URL/wp-json/cb/v1/download/$torrent_id")
    
    local success=$(echo "$dl_response" | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        local torrent_data=$(echo "$dl_response" | jq -r '.torrent_data')
        local filename=$(echo "$dl_response" | jq -r '.filename' | tr '<>:"/\\|?*' '_')
        
        mkdir -p "$DOWNLOAD_PATH"
        
        # Čekaj XBT sync
        log_warning "Čekanje 60s za XBT sinhronizaciju..."
        for i in 60 50 40 30 20 10; do
            log_gray "  Preostalo $i sekundi..."
            sleep 10
        done
        
        echo "$torrent_data" | base64 -d > "$DOWNLOAD_PATH/$filename"
        log_success "Torent sačuvan: $DOWNLOAD_PATH/$filename"
    fi
    
    echo ""
    log_success "═══════════════════════════════════════════"
    log_success "SVE ZAVRŠENO USPEŠNO!"
    log_success "═══════════════════════════════════════════"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    local source_path=""
    local torrent_name=""
    
    # Parsiraj argumente
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                torrent_name="$2"
                shift 2
                ;;
            -s|--screenshots)
                SCREENSHOT_COUNT="$2"
                shift 2
                ;;
            -a|--anonymous)
                ANONYMOUS=true
                shift
                ;;
            -c|--config)
                load_config
                config_wizard
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Nepoznata opcija: $1"
                usage
                exit 1
                ;;
            *)
                source_path="$1"
                shift
                ;;
        esac
    done
    
    # Proveri zavisnosti
    check_dependencies
    
    # Učitaj config
    load_config
    
    # Validacija
    if [ -z "$source_path" ]; then
        usage
        exit 1
    fi
    
    if [ ! -e "$source_path" ]; then
        log_error "Putanja ne postoji: $source_path"
        exit 1
    fi
    
    if [ -z "$API_KEY" ] || [ -z "$TMDB_API_KEY" ]; then
        log_error "API ključevi nisu podešeni. Pokreni: $0 --config"
        exit 1
    fi
    
    # Postavi naziv ako nije dat
    # search_name se uvek izvlači iz fajla/foldera za IMDB pretragu
    local search_name=$(basename "$source_path")
    search_name="${search_name%.*}"  # Ukloni ekstenziju
    search_name="${search_name//./ }"  # Zameni tačke sa razmacima
    
    if [ -z "$torrent_name" ]; then
        torrent_name="$search_name"
    fi
    
    # Pripremi radni folder
    mkdir -p "$WORK_DIR"
    rm -f "$WORK_DIR"/*.torrent
    rm -f "$WORK_DIR/imdb.txt"
    rm -f "$WORK_DIR/mediainfo.txt"
    rm -rf "$WORK_DIR/screenshots"
    
    echo ""
    log_info "═══════════════════════════════════════════"
    log_info "  CrnaBerza Torrent Uploader"
    log_info "═══════════════════════════════════════════"
    echo ""
    
    # Korak 1: Kreiranje torenta
    local item_name=$(basename "$source_path")
    local torrent_file="$WORK_DIR/${item_name}.torrent"
    create_torrent "$source_path" "$torrent_file" || exit 1
    echo ""
    
    # Pronađi video fajl
    local video_path=$(find_video_file "$source_path")
    if [ -z "$video_path" ]; then
        log_error "Video fajl nije pronađen"
        exit 1
    fi
    
    # Korak 2: Screenshot-ovi i MediaInfo
    local screenshots_dir="$WORK_DIR/screenshots"
    generate_screenshots "$video_path" "$screenshots_dir" "$SCREENSHOT_COUNT"
    
    local mediainfo_file="$WORK_DIR/mediainfo.txt"
    get_mediainfo "$video_path" "$mediainfo_file"
    echo ""
    
    # Korak 3: IMDB pretraga (koristi search_name iz fajla/foldera)
    local imdb_file="$WORK_DIR/imdb.txt"
    local tmdb_info
    
    if ! tmdb_info=$(search_imdb "$search_name" "$imdb_file"); then
        log_error "IMDB pretraga nije uspela"
        exit 1
    fi
    
    if [ ! -f "$imdb_file" ]; then
        log_error "IMDB fajl nije kreiran"
        exit 1
    fi
    
    local media_type=$(echo "$tmdb_info" | tail -1 | cut -d'|' -f1)
    local orig_lang=$(echo "$tmdb_info" | tail -1 | cut -d'|' -f2)
    local imdb_url=$(cat "$imdb_file")
    echo ""
    
    # Odredi kategoriju
    local category_id=$(detect_category "$mediainfo_file" "$media_type" "$orig_lang")
    echo ""
    
    # Korak 4: Upload
    upload_torrent "$torrent_file" "$torrent_name" "$imdb_url" "$category_id" "$mediainfo_file" "$screenshots_dir" "$ANONYMOUS"
}

main "$@"
