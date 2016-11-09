# ExchangeOnline-TraceLog-ImportandSCP

Powershell will be run from a windows machine capable of connecting to the exchange online ps session.

It will SCP the trace log in csv format to a logstash server

A script (process_input_logs.sh) will take care of avoiding duplication in the logs and give the csv to logstash

Logstash server will parse the CSV and insert into ElasticSearch database

Kibana will display the dashboard
