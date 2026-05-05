# ---- Build Stage ----
FROM public.ecr.aws/docker/library/node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci --quiet

COPY . .
RUN npm run build

# ---- Runtime Stage ----
FROM public.ecr.aws/docker/library/nginx:alpine
COPY --from=build /app/dist/frontend/browser /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
