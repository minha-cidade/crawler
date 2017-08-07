# Crawler
O Crawler tem a função de periodicamente baixar o banco de dados CSV da
[Transparência de João Pessoa](http://transparencia.joaopessoa.pb.gov.br/)
e armazenar seu conteúdo no banco de dados Mongo DB.

## Configuração
A configuração do crawler é enviada através das seguintes variáveis de ambiente:

* `CRAWLER_MONGO_CONNECTION_STRING` (default: `"mongodb://localhost"`)

  Endereço do banco de dados MongoDB seguindo o formato [Connection String](https://docs.mongodb.com/manual/reference/connection-string/).


* `CRAWLER_MONGO_DATABASE` (default: `"despesas"`)

  Nome do banco de dados usado pelo MongoDB.


* `CRAWLER_MONGO_COLLECTION` (default: `"gastometro"`)

  Nome da collection usada pelo MongoDB.


* `CRAWLER_SINGLE_RUN` (default: `"false"`)

  Executa o crawler apenas uma vez, sem iniciar o scheduler.

## Instalação
Na pasta do repositório, execute o seguinte comando para criar uma imagem docker
com o Crawler:

    $ docker build -t crawler .

Depois de criado a imagem, execute o seguinte comando para executar a aplicação
de forma interativa:

    $ docker run -it --name crawler
