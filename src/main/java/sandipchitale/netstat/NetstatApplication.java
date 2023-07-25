package sandipchitale.netstat;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnNotWebApplication;
import org.springframework.context.annotation.Bean;
import sandipchitale.netstat.service.NetstatService;

@SpringBootApplication
public class NetstatApplication {
	@Bean
	@ConditionalOnNotWebApplication
	public CommandLineRunner commandLineRunner(NetstatService netstatLineService) {
		return args -> {
			netstatLineService.getNetstatLines().forEach(System.out::println);
		};
	}
	public static void main(String[] args) {
		SpringApplication.run(NetstatApplication.class, args);
	}
}
