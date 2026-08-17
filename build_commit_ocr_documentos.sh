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

git commit -m "ocr-documentos: le CPF do recebedor no canhoto (Tesseract OCR) antes de confirmar entrega"
git push

echo "== pronto. acompanhe o deploy na Railway. =="
