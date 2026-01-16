# _____ build stage _____

FROM python:3.12-slim AS build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .

# Install dependencies as wheels
RUN pip install --no-cache-dir --upgrade pip \
 && pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt


# _____ final stage _____
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN addgroup --system app && adduser --system --ingroup app app

COPY --from=build /wheels /wheels

# Install deps from the pre-built wheels
RUN pip install --no-cache-dir /wheels/* \
 && rm -rf /wheels

COPY . .

USER app

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
