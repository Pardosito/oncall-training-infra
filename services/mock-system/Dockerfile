# syntax=docker/dockerfile:1
# Build from the repo root (pnpm workspace):
#   docker buildx build --platform linux/amd64 -f services/mock-system/Dockerfile .
# EKS nodes are x86_64; an arm64 image from a Mac fails with "exec format error".

FROM node:22-alpine AS build
RUN npm install -g pnpm@12.16.1
WORKDIR /repo

# Dependencies first, so code changes don't invalidate the install layer.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY services/mock-system/package.json services/mock-system/
RUN pnpm install --frozen-lockfile --filter "@oncall-training/mock-system..." --filter .

COPY services/mock-system/tsconfig.json services/mock-system/tsconfig.build.json services/mock-system/
COPY services/mock-system/src services/mock-system/src
RUN pnpm --filter "@oncall-training/mock-system" build \
 && pnpm --filter "@oncall-training/mock-system" deploy --prod /out

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /out/package.json ./
COPY --from=build /out/node_modules ./node_modules
COPY --from=build /repo/services/mock-system/dist ./dist

# Runs as non-root with a read-only root filesystem in Kubernetes; nothing writes to /app.
USER node
EXPOSE 8080
CMD ["node", "dist/main.js"]
