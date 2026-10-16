#!/bin/sh
# usage: tools/bust_cache.sh build/web/index.html <version>
# Makes a deploy reach players despite GitHub Pages' ten-minute caching and phones that
# hold pages longer:
#  - the engine script tag and every file the Godot web engine fetches (pck, wasm, audio
#    worklets) carry ?v=<version> through the GODOT_CONFIG locateFile hook, so a fresh
#    index.html never pairs with a stale pck;
#  - build/web/version.txt holds the version, and a snippet in index.html fetches it with
#    the cache bypassed on every load; when it differs from the page's own version the page
#    reloads itself once under a new query string, which skips the cached index.html too
#    (once per live version per tab, so a stale edge can never make it loop).
set -eu
html="$1"; version="$2"
dir=$(dirname "$html")
grep -q '"executable":"index"' "$html" || { echo "bust_cache: unexpected index.html" >&2; exit 1; }
printf '%s' "$version" > "$dir/version.txt"
sed -i \
  -e "s|<script src=\"index.js\"></script>|<script src=\"index.js?v=$version\"></script>|" \
  -e "s|\"executable\":\"index\"|\"executable\":\"index\",\"locateFile\":function(path){return path+\"?v=$version\";}|" \
  "$html"
upgrade="<script>(function(){var mine=\"$version\";var key=\"upgraded-to\";fetch(\"version.txt?t=\"+Date.now(),{cache:\"no-store\"}).then(function(r){return r.ok?r.text():mine;}).then(function(live){live=live.trim();if(!live||live===mine)return;try{if(sessionStorage.getItem(key)===live)return;sessionStorage.setItem(key,live);}catch(e){}location.replace(location.pathname+\"?v=\"+live+location.hash);}).catch(function(){});})();</script>"
python3 - "$html" "$upgrade" <<'PY'
import sys
path, snippet = sys.argv[1], sys.argv[2]
text = open(path).read()
assert "</head>" in text, "no </head> in index.html"
open(path, "w").write(text.replace("</head>", snippet + "\n</head>", 1))
PY
grep -q "locateFile" "$html" && grep -q "index.js?v=$version" "$html" && grep -q "version.txt" "$html"
echo "bust_cache: files are fetched as *?v=$version; version.txt written; self-upgrade snippet added"
