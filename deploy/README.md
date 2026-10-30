# Server für die Web-App und den LogisticsLab-Server

`setupServer.sh` richtet einen Linux-Server (Ubuntu 22.04/24.04, Debian 12) ein, auf dem die Web-Version von LogisticsLab Studio und der LogisticsLab-Server laufen – beide hinter nginx:

```
Browser --https--> nginx --+-- /      Web-App (statische Dateien aus flutter build web)
                           +-- /v1/   Proxy zu uvicorn 127.0.0.1:8000 (ein Worker) – mit dem API-Key der Nutzer
                                      oder (internes Netz) dem der Web-App
```

## Voraussetzungen

- VM mit Root-Zugang, DNS-Name, der auf die VM zeigt, Ports 80 und 443 offen. Größe: siehe unten.
- Ausgehender Zugriff auf GitHub, PyPI, die OSM-Server aus `confs/logisticsLab.yml` und Let's Encrypt.
- Ein GitHub-Token mit Lesezugriff auf `pyLogisticsLab`, `pyCmpl` und `LogisticsLabApp` (privat). Es wird nur während der Einrichtung für git und pip verwendet und nicht gespeichert.
- Die Web-App baut das Skript selbst: Es installiert Flutter (Version wie bei GitHub) nach `/opt/flutter`, falls es fehlt oder eine andere Version hat. Wer sie lieber auf dem eigenen Rechner baut: `flutter build web --release --no-web-resources-cdn` in LogisticsLabApp (ohne `--no-web-resources-cdn` lädt der Browser Teile der App von Google), `build/web` auf den Server kopieren und mit `--web` übergeben.

## Einrichten

```bash
sudo GITHUB_TOKEN=github_pat_... ./setupServer.sh \
     --domain logisticslab.example.org --email admin@example.org
```

| Option | Bedeutung |
|---|---|
| `--domain NAME` | Name des Servers, auch für das Zertifikat – ohne ihn nur http über die IP-Adresse |
| `--email ADRESSE` | für Let's Encrypt – ohne sie nur http |
| `--web DIR` | eine anderswo gebaute Web-App – ohne die Option baut das Skript sie selbst |
| `--flutter-version V` | Flutter-Version für den Bau auf dem Server (Default wie in `.github/workflows/desktop.yml`) |
| `--src DIR` | die Repositories nebeneinander (Default `/opt/logisticslab/src`, wird geklont bzw. aktualisiert) |
| `--max-problems N` | gleichzeitige Rechnungen (Default: CPUs − 1, mindestens 2) |
| `--no-tls` | kein Zertifikat, z. B. hinter einem anderen Proxy oder zum Test im lokalen Netz |
| `--internal-net CIDR` | ein Netz, dessen Nutzer keinen API-Key brauchen, z. B. `194.95.44.0/22` oder das VPN – mehrfach angebbar |
| `--open` | niemand braucht einen API-Key (z. B. ein Server nur im internen Netz) |

Das Skript

1. installiert nginx, Python, Compiler und certbot,
2. legt den Systembenutzer `loglab` und die Verzeichnisse an,
3. klont oder aktualisiert LogisticsLabApp, pyLogisticsLab und Cmpl2,
4. baut den CMPL-Kern mit HiGHS (`/opt/logisticslab/cmpl`),
5. richtet die Python-Umgebung mit pyCmpl und pyLogisticsLab samt Server ein (`/opt/logisticslab/venv`),
6. legt die Konfiguration in `/etc/logisticsLab` an, einen ersten API-Key `admin` (am Ende angezeigt, auch in `/etc/logisticsLab/admin.key`) und mit `--internal-net` oder `--open` einen für die Web-App,
7. baut die Web-App (installiert dafür bei Bedarf Flutter nach `/opt/flutter`) und kopiert sie nach `/var/www/logisticslab`,
8. richtet den systemd-Dienst `logisticslab` und die nginx-Seite ein, holt das Zertifikat,
9. prüft am Ende eine Anfrage über nginx: ohne Key 401 (der Server verlangt einen), mit `--internal-net`/`--open` 200.

**Aktualisieren:** dasselbe Kommando noch einmal – es holt die neuen Stände der Repositories und baut alles neu. Konfiguration und Keys bleiben erhalten. Nur `logPath`, `matrixCacheFile`, `maxProblems` und `debugging` in `logisticsLabServer.yml` setzt das Skript jedes Mal.

## Ohne eigene Domain

- **Nur http über die IP-Adresse:** `--domain` weglassen. nginx antwortet dann auf jede Adresse, ohne Zertifikat – gut im Hochschulnetz oder hinter einem VPN. Die Daten und eingegebene API-Keys gehen dann unverschlüsselt durchs Netz.
- **https mit einem Namen ohne eigene Domain:** Dienste wie nip.io oder sslip.io lösen z. B. `194-95-44-20.nip.io` auf die IP `194.95.44.20` auf. Mit `--domain 194-95-44-20.nip.io --email …` holt das Skript dafür ein Zertifikat von Let's Encrypt (der Server muss aus dem Internet über Port 80 erreichbar sein).
- **Auf Dauer:** eine Subdomain der Hochschule über die IT.

## Zugang: API-Keys

Der Server verlangt bei jeder Anfrage einen API-Key. Wer ihn braucht, legt das Skript fest:

| | wer braucht einen Key |
|---|---|
| Voreinstellung | alle |
| `--internal-net CIDR` | nur Zugriffe von außerhalb dieser Netze |
| `--open` | niemand |

- **Mit Key:** Die Nutzer tragen ihn in der App ein (Einstellungen → Rechnen → API-Key). Fehlt er oder ist er falsch, fragt die App beim Lösen danach. Der Key wird im Browser bzw. in der Desktop-App gespeichert.
- **Ohne Key (internes Netz, `--open`):** nginx setzt den Key der Web-App selbst ein (`/etc/nginx/conf.d/logisticslab-access.conf`, nur für root lesbar) – er erreicht den Browser nie. Alle diese Nutzer teilen sich ihn, seine Grenze `maxOpenProblems` ist deshalb so groß wie die Warteschlange (`maxQueueSize`).
- Gegen Vielnutzer hilft zusätzlich das Rate-Limit von nginx (10 Anfragen/s je IP).

**Keys verteilen** – zwei Varianten:

- *ein Key je Kurs*, mit Ablaufdatum zum Semesterende und einer Grenze offener Rechnungen für den ganzen Kurs, z. B. über Moodle verteilt. Einfach, schützt aber nur, solange er nicht weitergegeben wird.
- *ein Key je Person*: Die Grenze offener Rechnungen gilt dann je Person, dafür mehr Verwaltung.

```bash
K="sudo -u loglab LOGLAB_CONF_DIR=/etc/logisticsLab /opt/logisticslab/venv/bin/python /opt/logisticslab/src/pyLogisticsLab/logisticsLabServer/manageKeys.py"
$K add kurs-ws26 --expires 2027-03-31 --maxOpenProblems 60     # zeigt den Key einmal an
$K add mueller --expires 2027-03-31                            # je Person (Default: maxOpenProblemsPerKey)
$K list
$K disable kurs-ws26                                           # sperren, enable gibt wieder frei
```

Der Server liest die Keys ohne Neustart neu. Die Desktop-App erreicht den Server unter `https://logisticslab.example.org/v1/` (Einstellungen → Rechnen → Server).

## Betrieb

| | |
|---|---|
| Dienst | `systemctl status logisticslab`, `journalctl -u logisticslab -f` |
| Konfiguration | `/etc/logisticsLab/` (`logisticsLab.yml`, `logisticsLabServer.yml`, `apiKeys.yml`) |
| Logs | `/var/log/logisticsLab/` |
| Matrix-Cache | `/var/lib/logisticsLab/matrixCache.sqlite` |
| nginx | `/etc/nginx/sites-available/logisticslab` |

Nach Änderungen an der Konfiguration: `systemctl restart logisticslab`. API-Keys liest der Server ohne Neustart neu.

## Größe der VM

| | klein (Übung, ~30 Personen) | empfohlen (Vorlesung, ~100 Personen) |
|---|---|---|
| `--max-problems` | 4 | 8 |
| vCPU | 4–6 | 8–10 |
| RAM | 8 GB | 16 GB |
| SSD | 40 GB | 60 GB |

Flutter auf dem Server braucht etwa 3 GB Platz zusätzlich; der Bau der Web-App braucht kurz 2–4 GB RAM.

Ein eigener OSM-Routingdienst (ORS) ist nicht enthalten – der Server nutzt die ORS-Server aus `confs/logisticsLab.yml`.
