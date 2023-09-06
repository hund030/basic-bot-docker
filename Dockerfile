FROM node:18
WORKDIR .
COPY . .
RUN npm install
EXPOSE 443
CMD ["npm", "run", "start:teamsfx"]