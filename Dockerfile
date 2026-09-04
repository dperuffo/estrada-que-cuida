# Fase Deploy-Automático-PWA (04/09/2026, mesmo achado do Daniel já corrigido
# no PWA Cliente em 02/09: "por ser um PWA nao tem um comando diferente de
# commit e push? Ja tivemos problemas para atualizacao de PWAs") — este
# Dockerfile só copiava a pasta `build/web` já compilada do repo pro nginx.
# Isso exigia rodar `flutter build web` numa máquina LOCAL antes de todo
# commit — passo manual fácil de esquecer, e foi exatamente por isso que a
# correção da paleta clara (commit 7c4658c) não apareceu no site: o deploy
# teve sucesso, mas copiou o `build/web` antigo, de antes da mudança de cor.
#
# Agora o Railway builda o Flutter sozinho, na nuvem, a partir do
# pubspec.yaml — `git push` sozinho já é suficiente, sem passo manual.
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
