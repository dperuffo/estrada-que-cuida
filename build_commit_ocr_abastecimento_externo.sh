#!/bin/bash
set -e
cd "/Volumes/Daniel_Externo/Projetos/estrada-que-cuida"

echo "== flutter build web (isso e o que a Railway serve — sem isso nada muda no ar) =="
flutter clean
flutter build web --release

echo "== git =="
rm -f .git/index.lock .git/HEAD.lock .git/next-index-*.lock

git add -f build/web
git add -A

git status --porcelain -- build/web

git commit -m "build: recompila web com a tela de lancamento manual de abastecimento externo (OCR do cupom)"
git push

echo "== pronto. acompanhe o deploy na Railway. =="
