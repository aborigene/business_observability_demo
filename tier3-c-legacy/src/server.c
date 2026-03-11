#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/stat.h>
#include <errno.h>

#define PORT 8000
#define BUFFER_SIZE 65536
#define LOG_DIR "/var/log/loan-risk-engine"
#define LOG_FILE "/var/log/loan-risk-engine/app.log"
#define TIER4_HOST_ENV "TIER4_HOST"
#define TIER4_PORT_ENV "TIER4_PORT"
#define DEFAULT_TIER4_HOST "tier4-service"
#define DEFAULT_TIER4_PORT "8001"

// Simple JSON parser helpers
char* find_json_value(const char* json, const char* key) {
    char search_key[256];
    snprintf(search_key, sizeof(search_key), "\"%s\":", key);
    const char* key_pos = strstr(json, search_key);
    if (!key_pos) return NULL;
    
    const char* value_start = key_pos + strlen(search_key);
    while (*value_start == ' ' || *value_start == '\t') value_start++;
    
    if (*value_start == '"') {
        value_start++;
        const char* value_end = strchr(value_start, '"');
        if (!value_end) return NULL;
        int len = value_end - value_start;
        char* result = malloc(len + 1);
        strncpy(result, value_start, len);
        result[len] = '\0';
        return result;
    } else {
        const char* value_end = value_start;
        while (*value_end && *value_end != ',' && *value_end != '}' && *value_end != '\n' && *value_end != ' ') {
            value_end++;
        }
        int len = value_end - value_start;
        char* result = malloc(len + 1);
        strncpy(result, value_start, len);
        result[len] = '\0';
        return result;
    }
}

void get_timestamp(char* buffer, size_t size) {
    time_t now = time(NULL);
    struct tm* t = gmtime(&now);
    strftime(buffer, size, "%Y-%m-%dT%H:%M:%SZ", t);
}

void ensure_log_directory() {
    struct stat st = {0};
    if (stat(LOG_DIR, &st) == -1) {
        mkdir(LOG_DIR, 0755);
    }
}

void write_log(const char* level, const char* message, const char* applicationId,
               const char* customerId, const char* requestedAmount, const char* channel,
               const char* region, const char* costCenter, const char* team,
               const char* traceparent, const char* tier2Score, const char* tier3Score,
               long latencyMs) {
    
    FILE* log = fopen(LOG_FILE, "a");
    if (!log) {
        fprintf(stderr, "Failed to open log file: %s\n", strerror(errno));
        return;
    }
    
    char timestamp[64];
    get_timestamp(timestamp, sizeof(timestamp));
    
    fprintf(log, "{\"timestamp\":\"%s\",\"level\":\"%s\",\"service\":\"tier3-risk-analysis\","
            "\"tier\":\"tier3\",\"message\":\"%s\"",
            timestamp, level, message);
    
    if (applicationId) fprintf(log, ",\"applicationId\":\"%s\"", applicationId);
    if (customerId) fprintf(log, ",\"customerId\":\"%s\"", customerId);
    if (requestedAmount) fprintf(log, ",\"requestedAmount\":%s", requestedAmount);
    if (channel) fprintf(log, ",\"channel\":\"%s\"", channel);
    if (region) fprintf(log, ",\"region\":\"%s\"", region);
    if (costCenter) fprintf(log, ",\"costCenter\":\"%s\"", costCenter);
    if (team) fprintf(log, ",\"team\":\"%s\"", team);
    if (traceparent) fprintf(log, ",\"traceparent\":\"%s\"", traceparent);
    if (tier2Score) fprintf(log, ",\"tier2Score\":%s", tier2Score);
    if (tier3Score) fprintf(log, ",\"tier3Score\":%s", tier3Score);
    if (latencyMs >= 0) fprintf(log, ",\"latencyMs\":%ld", latencyMs);
    
    fprintf(log, "}\n");
    fclose(log);
}

int forward_to_tier4(const char* payload, const char* traceparent, const char* tracestate,
                     const char* applicationId, char* response_buffer, size_t buffer_size) {
    
    const char* tier4_host = getenv(TIER4_HOST_ENV);
    const char* tier4_port = getenv(TIER4_PORT_ENV);
    if (!tier4_host) tier4_host = DEFAULT_TIER4_HOST;
    if (!tier4_port) tier4_port = DEFAULT_TIER4_PORT;
    
    struct hostent* server = gethostbyname(tier4_host);
    if (!server) {
        fprintf(stderr, "Failed to resolve host: %s\n", tier4_host);
        return -1;
    }
    
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        fprintf(stderr, "Failed to create socket\n");
        return -1;
    }
    
    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    memcpy(&serv_addr.sin_addr.s_addr, server->h_addr, server->h_length);
    serv_addr.sin_port = htons(atoi(tier4_port));
    
    if (connect(sockfd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        fprintf(stderr, "Failed to connect to %s:%s\n", tier4_host, tier4_port);
        close(sockfd);
        return -1;
    }
    
    char request[BUFFER_SIZE];
    int len = snprintf(request, sizeof(request),
                      "POST /internal/decision/evaluate HTTP/1.1\r\n"
                      "Host: %s:%s\r\n"
                      "Content-Type: application/json\r\n"
                      "Content-Length: %zu\r\n",
                      tier4_host, tier4_port, strlen(payload));
    
    if (traceparent) {
        len += snprintf(request + len, sizeof(request) - len,
                       "traceparent: %s\r\n", traceparent);
    }
    if (tracestate) {
        len += snprintf(request + len, sizeof(request) - len,
                       "tracestate: %s\r\n", tracestate);
    }
    if (applicationId) {
        len += snprintf(request + len, sizeof(request) - len,
                       "x-application-id: %s\r\n", applicationId);
    }
    
    len += snprintf(request + len, sizeof(request) - len, "\r\n%s", payload);
    
    if (send(sockfd, request, len, 0) < 0) {
        fprintf(stderr, "Failed to send request\n");
        close(sockfd);
        return -1;
    }
    
    ssize_t n = recv(sockfd, response_buffer, buffer_size - 1, 0);
    close(sockfd);
    
    if (n < 0) {
        fprintf(stderr, "Failed to receive response\n");
        return -1;
    }
    
    response_buffer[n] = '\0';
    return 0;
}

void handle_request(int client_socket) {
    char buffer[BUFFER_SIZE];
    ssize_t bytes_read = recv(client_socket, buffer, sizeof(buffer) - 1, 0);
    
    if (bytes_read <= 0) {
        close(client_socket);
        return;
    }
    
    buffer[bytes_read] = '\0';
    
    // Parse headers
    char* traceparent = NULL;
    char* tracestate = NULL;
    char* line = strtok(buffer, "\r\n");
    char* body_start = NULL;
    
    while (line) {
        if (strncmp(line, "traceparent:", 12) == 0) {
            traceparent = strdup(line + 13);
            // Trim whitespace
            while (*traceparent == ' ') traceparent++;
        } else if (strncmp(line, "tracestate:", 11) == 0) {
            tracestate = strdup(line + 12);
            while (*tracestate == ' ') tracestate++;
        } else if (strlen(line) == 0) {
            body_start = line + 1;
            break;
        }
        line = strtok(NULL, "\r\n");
    }
    
    if (!body_start) {
        const char* error_response = "HTTP/1.1 400 Bad Request\r\n\r\n";
        send(client_socket, error_response, strlen(error_response), 0);
        close(client_socket);
        return;
    }
    
    clock_t start_time = clock();
    
    // Parse JSON body
    char* applicationId = find_json_value(body_start, "applicationId");
    char* customerId = find_json_value(body_start, "customerId");
    char* requestedAmount_str = find_json_value(body_start, "requestedAmount");
    char* channel = find_json_value(body_start, "channel");
    char* region = find_json_value(body_start, "region");
    char* costCenter = find_json_value(body_start, "costCenter");
    char* team = find_json_value(body_start, "team");
    char* tier2Score = find_json_value(body_start, "tier2Score");
    
    double requestedAmount = requestedAmount_str ? atof(requestedAmount_str) : 0.0;
    
    write_log("INFO", "Tier 3: Received advanced risk analysis request",
              applicationId, customerId, requestedAmount_str, channel, region,
              costCenter, team, traceparent, tier2Score, NULL, -1);
    
    // Generate tier3Score only if requestedAmount >= 10000
    int tier3Score = 0;
    char tier3Score_str[16];
    
    if (requestedAmount >= 10000.0) {
        srand(time(NULL) + getpid());
        tier3Score = rand() % 31;  // 0 to 30
        snprintf(tier3Score_str, sizeof(tier3Score_str), "%d", tier3Score);
        
        write_log("INFO", "Tier 3: Generated advanced risk score for high-value loan",
                  applicationId, customerId, requestedAmount_str, channel, region,
                  costCenter, team, traceparent, tier2Score, tier3Score_str, -1);
    } else {
        snprintf(tier3Score_str, sizeof(tier3Score_str), "0");
        write_log("INFO", "Tier 3: Skipped advanced analysis - loan amount below threshold",
                  applicationId, customerId, requestedAmount_str, channel, region,
                  costCenter, team, traceparent, tier2Score, tier3Score_str, -1);
    }
    
    // Build updated JSON with tier3Score
    char updated_json[BUFFER_SIZE];
    int json_len = strlen(body_start);
    if (body_start[json_len - 1] == '}') {
        snprintf(updated_json, sizeof(updated_json), "%.*s,\"tier3Score\":%s}",
                json_len - 1, body_start, tier3Score_str);
    } else {
        snprintf(updated_json, sizeof(updated_json), "%s,\"tier3Score\":%s}",
                body_start, tier3Score_str);
    }
    
    // Forward to Tier 4
    char tier4_response[BUFFER_SIZE];
    int forward_result = forward_to_tier4(updated_json, traceparent, tracestate,
                                         applicationId, tier4_response, sizeof(tier4_response));
    
    long latencyMs = (clock() - start_time) * 1000 / CLOCKS_PER_SEC;
    
    if (forward_result == 0) {
        write_log("INFO", "Tier 3: Successfully forwarded to Tier 4",
                  applicationId, customerId, requestedAmount_str, channel, region,
                  costCenter, team, traceparent, tier2Score, tier3Score_str, latencyMs);
        
        // Extract body from Tier 4 response
        char* tier4_body = strstr(tier4_response, "\r\n\r\n");
        if (tier4_body) {
            tier4_body += 4;
            char response[BUFFER_SIZE];
            snprintf(response, sizeof(response),
                    "HTTP/1.1 200 OK\r\n"
                    "Content-Type: application/json\r\n"
                    "Content-Length: %zu\r\n"
                    "\r\n%s",
                    strlen(tier4_body), tier4_body);
            send(client_socket, response, strlen(response), 0);
        }
    } else {
        write_log("ERROR", "Tier 3: Failed to forward to Tier 4",
                  applicationId, customerId, requestedAmount_str, channel, region,
                  costCenter, team, traceparent, tier2Score, tier3Score_str, latencyMs);
        
        const char* error_response = 
            "HTTP/1.1 502 Bad Gateway\r\n"
            "Content-Type: application/json\r\n"
            "\r\n{\"error\":\"Failed to forward to Tier 4\"}";
        send(client_socket, error_response, strlen(error_response), 0);
    }
    
    // Cleanup
    if (traceparent) free(traceparent);
    if (tracestate) free(tracestate);
    if (applicationId) free(applicationId);
    if (customerId) free(customerId);
    if (requestedAmount_str) free(requestedAmount_str);
    if (channel) free(channel);
    if (region) free(region);
    if (costCenter) free(costCenter);
    if (team) free(team);
    if (tier2Score) free(tier2Score);
    
    close(client_socket);
}

int main() {
    ensure_log_directory();
    
    write_log("INFO", "Tier 3: Advanced Risk Analysis Service starting",
              NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, -1);
    
    int server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket < 0) {
        fprintf(stderr, "Failed to create socket\n");
        return 1;
    }
    
    int opt = 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(PORT);
    
    if (bind(server_socket, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        fprintf(stderr, "Failed to bind to port %d\n", PORT);
        return 1;
    }
    
    if (listen(server_socket, 10) < 0) {
        fprintf(stderr, "Failed to listen\n");
        return 1;
    }
    
    printf("Tier 3 - Advanced Risk Analysis Service listening on port %d\n", PORT);
    write_log("INFO", "Tier 3: Service ready to accept connections",
              NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, -1);
    
    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_socket = accept(server_socket, (struct sockaddr*)&client_addr, &client_len);
        
        if (client_socket < 0) {
            fprintf(stderr, "Failed to accept connection\n");
            continue;
        }
        
        handle_request(client_socket);
    }
    
    close(server_socket);
    return 0;
}
