# curl-cffi-deb

Automatisch gebaute Debian-/Ubuntu-Pakete (`python3-curl-cffi`) für
[curl_cffi](https://github.com/lexiforest/curl_cffi) – den Python-HTTP-Client
mit Browser-Impersonation (TLS/JA3- und HTTP/2-Fingerprints).

## Wie es funktioniert

- Eine GitHub Action prüft **täglich** die neueste stabile Version auf PyPI.
- Gibt es dafür noch kein Release, wird das `.deb` für **amd64, arm64 und armhf** gebaut.
- Jedes Paket wird in frischen Containern mit **Debian 12, Debian 13 und Ubuntu 24.04**
  installiert, getestet und wieder entfernt.
- Erst wenn alle Tests grün sind, entsteht ein Release `v<version>-<revision>`
  mit den `.deb`-Dateien und einer `SHA256SUMS`.

Es wird nichts kompiliert: Das Paket enthält das offizielle manylinux-abi3-Wheel
(libcurl-impersonate ist darin statisch gelinkt). `cffi` und `certifi` kommen aus
den Distro-Paketen. Upstream fordert zwar `cffi>=2.0`, läuft aber mit dem cffi 1.x
von Debian/Ubuntu. Die Metadaten werden entsprechend angepasst, damit `pip check`
nicht meckert.

## Installation

Das passende `.deb` aus den [Releases](../../releases/latest) laden, dann:

```bash
sudo apt install ./python3-curl-cffi_*_$(dpkg --print-architecture).deb
```

Voraussetzung: Python ≥ 3.10 (Debian 12+, Ubuntu 22.04+, Raspberry Pi OS Bookworm+).

```python
from curl_cffi import requests
r = requests.get("https://example.com", impersonate="chrome")
```

Das CLI `curl-cffi` liegt danach in `/usr/bin`. Für die farbige Ausgabe optional
`python3-rich` installieren.

## Manuell bauen

```bash
./build-deb.sh 0.16.3 amd64        # Version, Architektur [, Revision, Ausgabeordner]
```

Oder in GitHub unter *Actions → Build curl_cffi .deb → Run workflow*, optional mit
fester Version, neuer Debian-Revision oder `force` für einen Neubau.
