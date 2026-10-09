wget https://testfileorg.netwet.net/500MB-CZIPtestfile.org.zip
token=$(curl -s -X POST http://161.33.170.140/api/login -H "Content-Type: application/json" -d '{"username":"test", "password":"CZHalpBm007XVef1"}')
while true; do
    random_string=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 10)
    echo "$random_string"
curl -X POST http://161.33.170.140/api/resources/test/${random_string} \
  -H "X-Auth: $token" \
  --data-binary "@500MB-CZIPtestfile.org.zip"
done
