FROM nginx:alpine

COPY target/site/ /usr/share/nginx/html/

EXPOSE 80
