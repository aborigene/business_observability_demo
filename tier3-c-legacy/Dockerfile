FROM public.ecr.aws/docker/library/alpine:3.19 AS build
WORKDIR /app
RUN apk add --no-cache gcc musl-dev make
COPY Makefile .
COPY src/ ./src/
RUN make

FROM public.ecr.aws/docker/library/alpine:3.19
WORKDIR /app
RUN mkdir -p /var/log/loan-risk-engine && chmod 777 /var/log/loan-risk-engine
COPY --from=build /app/loan-risk-server .
EXPOSE 8000
CMD ["./loan-risk-server"]
