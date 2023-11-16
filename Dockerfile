ARG NODE_VERSION=18.18.0
ARG ALPINE_VERSION=3.17

# The build image
FROM node:${NODE_VERSION} AS build
WORKDIR /usr/src/app
COPY package*.json /usr/src/app/
RUN npm ci --only=production

# The production image
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION}
# Add required binaries
RUN apk add --no-cache libstdc++ dumb-init
# Run with dumb-init to not start node with PID=1, since Node.js was not designed to run as PID 1
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
ENV NODE_ENV production
USER node
WORKDIR /usr/src/app
COPY --chown=node:node --from=build /usr/src/app/node_modules /usr/src/app/node_modules
COPY --chown=node:node . /usr/src/app
CMD ["node", "index.js"]