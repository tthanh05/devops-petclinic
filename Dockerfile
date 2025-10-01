FROM eclipse-temurin:17-jre-jammy AS runtime
WORKDIR /app

# Copy the fat jar built by Jenkins (adjust glob if needed)
COPY target/spring-petclinic-*.jar app.jar

# Expose the app port (now 8085)
EXPOSE 8085

# Run Spring Boot on 8085 inside the container
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dserver.port=8085"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
