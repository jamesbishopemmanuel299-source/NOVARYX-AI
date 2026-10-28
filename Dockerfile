FROM node:22-alpine
WORKDIR /app
COPY backend/package.json ./package.json
COPY backend/server.js ./server.js
COPY backend/public ./public
ENV NODE_ENV=production
EXPOSE 10000
CMD ["npm", "start"]
