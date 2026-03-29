package com.github.bedrockgateway.config;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "gateway")
public class GatewayProperties {

    private List<ApiKeyConfig> apiKeys = new ArrayList<>();
    private Map<String, AccountConfig> accounts = new HashMap<>();
    private Map<String, String> modelMapping = new HashMap<>();
    private List<String> supportedBetaFlags = new ArrayList<>();
    private LoggingConfig logging = new LoggingConfig();

    public List<ApiKeyConfig> getApiKeys() { return apiKeys; }
    public void setApiKeys(List<ApiKeyConfig> apiKeys) { this.apiKeys = apiKeys; }
    public Map<String, AccountConfig> getAccounts() { return accounts; }
    public void setAccounts(Map<String, AccountConfig> accounts) { this.accounts = accounts; }
    public Map<String, String> getModelMapping() { return modelMapping; }
    public void setModelMapping(Map<String, String> modelMapping) { this.modelMapping = modelMapping; }
    public List<String> getSupportedBetaFlags() { return supportedBetaFlags; }
    public void setSupportedBetaFlags(List<String> supportedBetaFlags) { this.supportedBetaFlags = supportedBetaFlags; }
    public LoggingConfig getLogging() { return logging; }
    public void setLogging(LoggingConfig logging) { this.logging = logging; }

    public static class ApiKeyConfig {
        private String key;
        private String name;
        private int rateLimitPerMinute = 60;
        private String route = "default";

        public String getKey() { return key; }
        public void setKey(String key) { this.key = key; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public int getRateLimitPerMinute() { return rateLimitPerMinute; }
        public void setRateLimitPerMinute(int rateLimitPerMinute) { this.rateLimitPerMinute = rateLimitPerMinute; }
        public String getRoute() { return route; }
        public void setRoute(String route) { this.route = route; }
    }

    public static class AccountConfig {
        private String region = "us-east-1";
        private String roleArn;
        private String profile;

        public String getRegion() { return region; }
        public void setRegion(String region) { this.region = region; }
        public String getRoleArn() { return roleArn; }
        public void setRoleArn(String roleArn) { this.roleArn = roleArn; }
        public String getProfile() { return profile; }
        public void setProfile(String profile) { this.profile = profile; }
    }

    public static class LoggingConfig {
        private boolean logRequestBody = false;
        private boolean logResponseBody = false;
        private boolean logUsage = true;

        public boolean isLogRequestBody() { return logRequestBody; }
        public void setLogRequestBody(boolean logRequestBody) { this.logRequestBody = logRequestBody; }
        public boolean isLogResponseBody() { return logResponseBody; }
        public void setLogResponseBody(boolean logResponseBody) { this.logResponseBody = logResponseBody; }
        public boolean isLogUsage() { return logUsage; }
        public void setLogUsage(boolean logUsage) { this.logUsage = logUsage; }
    }
}
