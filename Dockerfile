# ============== STAGE 1: Build the application ==============
FROM maven:3.9-eclipse-temurin-17 AS builder

# Set working directory
WORKDIR /app

# Copy pom.xml and download dependencies first (caching)
COPY pom.xml .
RUN mvn -B dependency:go-offline

# Copy application source code
COPY src ./src

# Build the Spring Boot application
RUN mvn -B -DskipTests package


# ============== STAGE 2: Create runtime image ==============
FROM eclipse-temurin:17-jdk

# Create directory for the app
WORKDIR /app

# Copy the jar file from the builder stage
COPY --from=builder /app/target/*.jar app.jar

# Expose the application port
EXPOSE 8080

# Use non-root user if needed
USER 1001

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
