FROM perl:5.22

COPY . /app
WORKDIR /app

RUN apt-get update \
	&& apt-get install -y unzip \
	&& cpanm App::cpm \
	&& cpm install -g

CMD ["perl", "crawler.pl"]
