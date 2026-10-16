#!/bin/sh
# usage: tools/bust_cache.sh build/web/index.html <version>
# Appends ?v=<version> to the engine script tag and to every file the Godot web engine
# fetches (pck, wasm, audio worklets) through the GODOT_CONFIG locateFile hook, so a new
# deploy is never served from a browser's cache of the previous one.
set -eu
html="$1"; version="$2"
grep -q '"executable":"index"' "$html" || { echo "bust_cache: unexpected index.html" >&2; exit 1; }
sed -i \
  -e "s|<script src=\"index.js\"></script>|<script src=\"index.js?v=$version\"></script>|" \
  -e "s|\"executable\":\"index\"|\"executable\":\"index\",\"locateFile\":function(path){return path+\"?v=$version\";}|" \
  "$html"
grep -q "locateFile" "$html" && grep -q "index.js?v=$version" "$html"
echo "bust_cache: files are fetched as *?v=$version"
