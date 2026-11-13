#!/usr/bin/env bash
# Сборка latest.json для автообновления приложения.
#
# Файл описывает, какой пакет и с какой подписью скачивать на каждой платформе.
# Раньше его генерировал tauri-action в каждом платформенном job: четыре платформы
# параллельно писали и удаляли один файл в черновике релиза, и сборка падала с
# «Not Found — get a release asset». Теперь файл собирается один раз, после всех
# сборок, из подписей уже загруженных файлов.
#
#   bash scripts/build-latest-json.sh v0.8.2
set -euo pipefail

tag="${1:?Укажите тег, например v0.8.2}"
version="${tag#v}"
repo="${REPO:?REPO не задан}"
base="https://github.com/$repo/releases/download/$tag"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Подписи всех загруженных файлов.
gh release download "$tag" -R "$repo" --pattern "*.sig" -D "$tmp/sigs"

# Имя файла платформы в релизе (по шаблону).
asset() {
	gh release view "$tag" -R "$repo" --json assets --jq '.assets[].name' \
		| grep -E "$1" | head -n1
}

# Подпись платформы: содержимое соответствующего .sig (одна строка, base64).
signature() {
	head -n1 "$tmp/sigs/$1.sig" | tr -d '\r\n'
}

nsis="$(asset '_x64-setup\.exe$')"
msi="$(asset '\.msi$')"
appimage="$(asset '\.AppImage$')"
deb="$(asset '\.deb$')"
rpm="$(asset '\.rpm$')"

for pair in "nsis:$nsis" "msi:$msi" "appimage:$appimage" "deb:$deb" "rpm:$rpm"; do
	name="${pair#*:}"
	if [ -z "$name" ] || [ ! -f "$tmp/sigs/$name.sig" ]; then
		echo "✗ Нет файла или подписи: ${pair%%:*} (${name:-не найден})" >&2
		exit 1
	fi
done

notes="$(gh release view "$tag" -R "$repo" --json body --jq .body)"

# Описание релиза в JSON-строке (экранирование кавычек и переносов).
notes_json="$(printf '%s' "$notes" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>process.stdout.write(JSON.stringify(d)))')"

cat > "$tmp/latest.json" <<JSON
{
  "version": "$version",
  "notes": $notes_json,
  "pub_date": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "platforms": {
    "darwin-aarch64": { "signature": "$(signature Axiom_aarch64.app.tar.gz)", "url": "$base/Axiom_aarch64.app.tar.gz" },
    "darwin-aarch64-app": { "signature": "$(signature Axiom_aarch64.app.tar.gz)", "url": "$base/Axiom_aarch64.app.tar.gz" },
    "darwin-x86_64": { "signature": "$(signature Axiom_x64.app.tar.gz)", "url": "$base/Axiom_x64.app.tar.gz" },
    "darwin-x86_64-app": { "signature": "$(signature Axiom_x64.app.tar.gz)", "url": "$base/Axiom_x64.app.tar.gz" },
    "windows-x86_64": { "signature": "$(signature "$nsis")", "url": "$base/$nsis" },
    "windows-x86_64-nsis": { "signature": "$(signature "$nsis")", "url": "$base/$nsis" },
    "windows-x86_64-msi": { "signature": "$(signature "$msi")", "url": "$base/$msi" },
    "linux-x86_64": { "signature": "$(signature "$appimage")", "url": "$base/$appimage" },
    "linux-x86_64-appimage": { "signature": "$(signature "$appimage")", "url": "$base/$appimage" },
    "linux-x86_64-deb": { "signature": "$(signature "$deb")", "url": "$base/$deb" },
    "linux-x86_64-rpm": { "signature": "$(signature "$rpm")", "url": "$base/$rpm" }
  }
}
JSON

node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$tmp/latest.json"
cp "$tmp/latest.json" latest.json
echo "✓ latest.json собран для $version"
