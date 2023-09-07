FROM node:18
WORKDIR .
COPY . .
RUN npm install
EXPOSE 443
ENV PORT=443 SERVER_CERT_FILE="./certs/server-cert.pem" SERVER_KEY_FILE="./certs/server-key.pem"
CMD ["npm", "run", "start:teamsfx"]