# Observer MeshCore: Cisien/meshcoretomqtt (mctomqtt) em container.
# app/ = cópia sem alterações do upstream (versão em app/.version_info).
FROM python:3.14-slim
RUN pip install --no-cache-dir ed25519-orlp==0.1.3 paho-mqtt==2.1.0 pyserial==3.5
WORKDIR /opt/mctomqtt
COPY app/ /opt/mctomqtt/
ENV PYTHONUNBUFFERED=1
CMD ["python3", "/opt/mctomqtt/mctomqtt.py"]
