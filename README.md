chmod +x *.sh


docker compose up -d $(seq -f "dc-arx-node-%g" 1 50)
