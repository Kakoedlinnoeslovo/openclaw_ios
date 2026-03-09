FROM node:22-slim
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
RUN npm install -g clawhub@latest
COPY . .
EXPOSE 3000
CMD ["node", "src/index.js"]
