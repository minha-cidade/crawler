#!/usr/bin/env perl
use strict;
use warnings;

use utf8;
use v5.22;
use MongoDB;
use Text::CSV;
use Text::Unidecode;
use Schedule::Cron;
use Try::Tiny;

# Ativa moto UTF-8 no STDOUT
binmode(STDOUT, ":utf8");

# Constantes
use constant {
	DOWNLOAD_URL => "http://transparencia.joaopessoa.pb.gov.br/sicoda/sql_dumps/lei131.csv.zip",
	ZIP_PATH     => "/tmp/despesas-jp.csv.zip",
	CSV_FILENAME => "despesa_lei131.csv",
	CSV_PATH     => "/tmp/despesa_lei131.csv",
};


# Conecta ao banco de dados
my $mongodb_connection_string = $ENV{CRAWLER_MONGO_CONNECTION_STRING}
	|| "mongodb://localhost";
my $mongodb_database   = $ENV{CRAWLER_MONGO_DATABASE}   || "despesas";
my $mongodb_collection = $ENV{CRAWLER_MONGO_COLLECTION} || "gastometro";

say "Conectando ao banco de dados";
my $client = MongoDB->connect($mongodb_connection_string)
	or die "Falha conectando ao servidor MongoDB";
my $collection = $client->ns("$mongodb_database.$mongodb_collection");


# Realiza o processo de crawling
sub crawl {
	# Baixa o resultado
	say "Baixando CSV do site da transparência";
	system("wget", "-q", DOWNLOAD_URL, "-O", ZIP_PATH) == 0
		or die "Falha baixando arquivo " . DOWNLOAD_URL;


	# Descompacta o arquivo
	say "Desempacotando arquivo";
	system("unzip", "-qq", "-o", ZIP_PATH, CSV_FILENAME, "-d", "/tmp") == 0
		or die "Falha desempacotado arquivo";


	# Cria o leitor CSV
	say "Lendo arquivo CSV";
	my $csv = Text::CSV->new ({
		binary => 1,
		sep    => "|",
	})
		or die "Cannot use CSV: ".Text::CSV->error_diag ();


	# Abre o arquivo
	open my $fh, "<:encoding(utf8)", CSV_PATH
		or die "Falha lendo CSV: $!";

	my %data;
	while (my $row = $csv->getline($fh)) {
		# Extrai as informações importantes da linha
		my $transacao = $row->[20];
		my $area      = $row->[25];
		my $valor     = $row->[22];
		my $ano       = $row->[0];

		# Caso a transação seja um pagamento de empenho
		if ($transacao eq "Pagamento de Empenho") {
			$data{$ano}{$area}{pago} += abs($valor);

			# Adiciona a lista de transações, para depois ser realizado o sorting
			# dos maiores vinte resultados
			push @{ $data{$ano}{$area}{pagamentos} //= [] }, {
				favorecido => $row->[9],
				pagante    => $row->[3],
				valor      => $valor,
			};
		}
		# Caso a transação seja um estorno de pagamento de empenho
		elsif ($transacao eq "Estorno de Pagamento de Empenho") {
			$data{$ano}{$area}{pago} -= abs($valor);
		}
		# Caso a transação seja uma liquidação de empenho
		elsif ($transacao eq "Liquidacao de Empenho") {
			$data{$ano}{$area}{liquidado} += abs($valor);
		}
		# Caso a transação seja um estorno de liquidação de empenho
		elsif ($transacao eq "Estorno de Liquidacao de Empenho") {
			$data{$ano}{$area}{liquidado} -= abs($valor);
		}
		# Caso a transação seja a emissão de um empenho
		elsif ($transacao eq "Emissao de Empenho") {
			$data{$ano}{$area}{empenhado} += abs($valor);
		}
	}


	# Envia os dados
	say "Limpando a coleção do Mongo";
	$collection->delete_many({ });

	say "Enviando dados para o Mongo";
	while (my ($ano, $data_ano) = each %data) {
		while (my ($area, $gastometro) = each %$data_ano) {
			# Formata o id da area
			my $id_area = unidecode(lc $area);
			$id_area =~ tr/ /-/;

			# Insere um resultado no mongo
			$collection->insert_one({
				ano => 0 + $ano,

				cidade => "João Pessoa",
				estado => "Paraíba",
				area   => lc $area,

				idCidade => "joao-pessoa",
				idEstado => "pb",
				idArea   => $id_area,

				liquidado => 0 + (sprintf "%.2f", $gastometro->{liquidado} // 0.0),
				empenhado => 0 + (sprintf "%.2f", $gastometro->{empenhado} // 0.0),
				pago      => 0 + (sprintf "%.2f", $gastometro->{pago}      // 0.0),

				# Realiza o sorting dos resultados e armazena apenas os vinte
				# maiores
				topVinte => [
					(sort { $b->{valor} <=> $a->{valor} }
						@{ $gastometro->{pagamentos} })[0..19]
				],
			});
		}
	}

	say "Desconectando e limpando arquivos";
	unlink ZIP_PATH, CSV_PATH;
	close $fh;
}

# Wrapper que evita erros fatais do crawler de fechar o programa
sub work {
	try {
		crawl
	}
	catch {
		say "Falha realizando crawling: $_";
	};
}

# Executa o script uma vez
say "Executando script pela primeira vez";
work;

# Caso a variável de ambiente CRAWLER_SINGLE_RUN estiver definida como true,
# não inicia o cron para executar o script em loop
if (!defined $ENV{CRAWLER_SINGLE_RUN} && $ENV{CRAWLER_SINGLE_RUN} ne 'true') {
	say "Programando próxima execução para 24:00";
	my $cron = Schedule::Cron->new(\&work);
	$cron->add_entry("0 0 * * *");
	$cron->run;
}
