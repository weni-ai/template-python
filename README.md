# template-python

Repositorio com codigo em python para servir de modelo e boas praticas no desenvolvimento de aplicações com foco em uma infraestrutura adaptada para boas praticas de cloud.

## Requisitos

- [ ] Health Check para todos os serviços
- [ ] Não executar como root
- [x] Um processo por container
- [x] Filas para celery
- [ ] Exemplo para k8s
- [x] Exemplo para docker-compose
- [ ] Exportar metricas
- [ ] Teste de loadbalancer para backend
- [x] Cache de frontend
- [ ] Escalabilidade automática horizontal
- [x] Dockerfile Build em multiestágio
- [x] `.dockerignore` excluindo arquivos principais(git e outras informações sensíveis)
- [x] `.gitignore` com arquivos de editor e outros desnecessários
- [x] Imagem pequena
- [x] gunicorn com poucos processos de workers
- [x] gunicorn com max-requests habilitado
- [x] gunicorn com logs de acesso
- [x] gunicorn com erro para a saída padrão
- [x] limites configurados

