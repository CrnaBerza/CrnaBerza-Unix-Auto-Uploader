# CrnaBerza Torrent Uploader

Bash skripta za automatski upload torenata na CrnaBerza tracker. Konvertovano sa PowerShell GUI verzije za Linux/Debian.

## Funkcionalnosti

- Automatsko kreiranje .torrent fajla
- Generisanje screenshot-ova iz videa
- Ekstrakcija MediaInfo podataka
- Automatska IMDB pretraga preko TMDB API-ja
- Auto-detekcija kategorije (Film/TV, HD/SD, Domaće/Strano)
- Detekcija titlova (srpski, hrvatski, bosanski)
- Upload na CrnaBerza API sa screenshot-ovima

## Instalacija

### Debian/Ubuntu

```bash
# Instaliraj potrebne pakete
sudo apt update
sudo apt install mktorrent ffmpeg mediainfo jq curl bc

# Preuzmi skriptu
curl -O https://github.com/CrnaBerza/CrnaBerza-Unix-Auto-Uploader/main/cb-upload.sh

chmod +x cb-upload.sh

# Podesi API ključeve
./cb-upload.sh --config
```

### Potrebni API ključevi

- **CrnaBerza API Key** - dobija se na sajtu
- **TMDB API Key** - besplatno na [themoviedb.org](https://www.themoviedb.org/settings/api)

## Upotreba

```bash
# Osnovni upload
./cb-upload.sh /putanja/do/filma.mkv

# Upload foldera
./cb-upload.sh /putanja/do/foldera/

# Sa custom nazivom
./cb-upload.sh -n "Naziv Filma (2024) 1080p WEB-DL" /putanja/do/filma.mkv

# Anonimni upload sa 5 screenshot-ova
./cb-upload.sh -a -s 5 /putanja/do/filma.mkv

# Sve opcije
./cb-upload.sh -n "Naziv" -s 10 -a /putanja/
```

### Opcije

| Opcija | Opis |
|--------|------|
| `-n, --name NAME` | Custom naziv torenta |
| `-s, --screenshots N` | Broj screenshot-ova (default: 10) |
| `-a, --anonymous` | Anonimni upload |
| `-c, --config` | Pokreni config wizard |
| `-h, --help` | Prikaži pomoć |

## Konfiguracija

Konfiguracija se čuva u `config.json` pored skripte:

```json
{
    "work_dir": "/home/user/cb-uploader/work",
    "download_path": "/home/user/Downloads/torrents",
    "announce_url": "http://www.crnaberza.com/announce",
    "base_url": "https://www.crnaberza.com",
    "api_key": "TVOJ_API_KEY",
    "tmdb_api_key": "TVOJ_TMDB_KEY"
}
```

## Kako radi

1. **Kreiranje torenta** - koristi `mktorrent` sa private flag-om
2. **Screenshot-ovi** - `ffmpeg` pravi 10 screenshot-ova ravnomerno raspoređenih
3. **MediaInfo** - ekstrahuje tehničke podatke o videu
4. **IMDB pretraga** - traži film/seriju na TMDB, dobija IMDB link
5. **Auto-kategorija** - određuje HD/SD po širini (≥1280px = HD), Film/TV po TMDB tipu, Domaće/Strano po originalnom jeziku
6. **Upload** - šalje sve na CrnaBerza API, preuzima torrent sa passkey-em

## Podržane kategorije

| Kategorija | ID |
|------------|-----|
| Film HD Domaće | 73 |
| Film HD Strano | 48 |
| Film SD Domaće | 29 |
| Film SD Strano | 54 |
| TV HD Domaće | 75 |
| TV HD Strano | 77 |
| TV SD Domaće | 30 |
| TV SD Strano | 34 |

## Troubleshooting

### "Error creating thread: Resource temporarily unavailable"
Skripta koristi `-t 2` za mktorrent. Ako i dalje ima problema, smanji na `-t 1`.

### "TMDB pretraga nije vratila rezultate"
Proveri da li je TMDB API key ispravan i da li naziv fajla/foldera sadrži ime filma.

### "Argument list too long"
Skripta koristi fajlove umesto argumenata za velike base64 podatke. Ako se pojavi, prijavi bug.

## Zavisnosti

- `mktorrent` - kreiranje torrent fajlova
- `ffmpeg` / `ffprobe` - screenshot-ovi i video info
- `mediainfo` - tehnički podaci o videu
- `jq` - JSON procesiranje
- `curl` - API pozivi
- `bc` - matematičke operacije

## Licenca

MIT

## Autor

Konvertovano sa PowerShell verzije za Linux/Debian.
