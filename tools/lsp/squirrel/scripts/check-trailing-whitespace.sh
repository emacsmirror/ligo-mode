#!/usr/bin/env bash

files=$(git ls-files | xargs grep --files-with-matches --binary-files=without-match '[[:blank:]]$')
if [[ -n $files ]];then
  echo '  Files with trailing whitespace found:'
  for f in "${files[@]}"; do
    echo "  * $f"
  done
  exit 1
fi
