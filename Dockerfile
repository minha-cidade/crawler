FROM perl:5.22

COPY . /app
WORKDIR /app

RUN cpanm --installdeps . -n

CMD ["perl", "script.pl"]
