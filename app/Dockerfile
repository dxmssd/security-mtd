#===== The builder ======
FROM python:3.11-slim AS builder
WORKDIR /app

#===== Install dependence ====
COPY requirements.txt .
RUN pip  install --no-cache-dir --user -r requirements.txt


#===== Runtime =========
FROM python:3.11-slim-bookworm
#==== Users privileges ====
RUN groupadd -r mtd_user && useradd -r -g mtd_user mtd_user

WORKDIR /app

#we copy what is neccesary from the previous stage
COPY --from=builder /root/.local /home/mtd_user/.local
COPY . .

#mtd_ser is the absolte owner of everything inside the /app folder
RUN chown -R mtd_user:mtd_user /app #
USER mtd_user

# Variables that ArgoCD/Kubernetes will inject to scale
ENV PATH=/home/mtd_user/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    APP_PORT=8080 \
    MTD_ROTATION_ID=initial_state


EXPOSE 8080

# Guinicorn server for scaling
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
