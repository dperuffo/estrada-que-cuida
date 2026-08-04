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
git commit -m "reorganizacao-menu: agrupar menu lateral por tema (5 grupos)"
git push

echo "== confirmando o que foi commitado (deve mostrar build/web/main.dart.js com muitas linhas) =="
git show --stat HEAD | head -20

echo "== pronto. acompanhe o deploy na Railway. =="
