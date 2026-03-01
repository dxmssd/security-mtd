#===== The builder ======
FROM python:3.11-slim AS builder
WORKDIR /app

#===== Install dependence ====
COPY app/requirements.txt .
RUN pip  install --no-cache-dir --user -r requirements.txt


#===== Runtime =========
FROM python:3.11-slim-bookworm
#==== Users privileges ====
RUN groupadd -r mtd_user && useradd -r -g mtd_user mtd_user
WORKDIR /app

#we copy what is neccesary from the previous stage
COPY --from=builder /root/.local /home/mtd_user/.local
COPY /app .

#mtd_ser is the absolte owner of everything inside the /app folder
RUN chown -R mtd_user:mtd_user /app /home/mtd_user/.local


# Variables that ArgoCD/Kubernetes will inject to scale
ENV PATH=/home/mtd_user/.local/bin:$PATH \
    PYTHONPATH="/app" \
    PYTHONUNBUFFERED=1
    PATH="/home/mtd_user/.local/bin:${PATH}"

USER mtd_user

EXPOSE 8080

# Guinicorn server for scaling
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
