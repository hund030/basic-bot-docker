FROM node:18
WORKDIR .
COPY . .
RUN npm install
EXPOSE 80
ENV PORT=80
CMD ["npm", "run", "start:teamsfx"]