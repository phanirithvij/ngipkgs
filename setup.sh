rm -rf data
mkdir -p data/{db,media,consume,logs}
export DATA_DIR=$PWD/data
export LOGS_DIR=$DATA_DIR/logs # ideally /var/logs/pdfding not /var/lib/pdfding/logs

export SECRET_KEY="some_long_random_secret"
# ALLOWED_HOSTS
export HOST_NAME="127.0.0.1,localhost,0.0.0.0"
export HOST="0.0.0.0"
export PORT=8111
export WORKERS=3

# TODO these need to be killed or what? they are getting made everytime service restarts
./result-p/bin/supervisord -c ./result-p/share/supervisord.conf

./result-p/bin/pdfding-manage migrate
./result-p/bin/pdfding-manage clean_up

exec ./result-p/bin/pdfding-start
