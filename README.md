# rkn_request
# Description
Скачивание списка запрещенных сайтов с сервиса "Роскомнадзор"
# How to use
```sh
./rkn_request.sh -p ./file.pem -e user@example.net -n "ОАО 'Контора'"
```
# Required
iconv openssl base64 curl libgost_engine.so

# OpenSSL GOST engine
https://github.com/gost-engine/engine
