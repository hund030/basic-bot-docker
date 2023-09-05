FROM node:18
WORKDIR .
COPY . .
RUN npm install
EXPOSE 3978
CMD ["npm", "run", "dev:teamsfx"]