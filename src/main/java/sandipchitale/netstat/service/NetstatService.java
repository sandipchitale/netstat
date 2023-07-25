package sandipchitale.netstat.service;

import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.stereotype.Service;
import sandipchitale.netstat.model.NetstatLine;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.LinkedList;
import java.util.List;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.ExecutorService;

@Service
public class NetstatService implements InitializingBean, DisposableBean {
    private Process netstatProcess;
    List<NetstatLine> netstatLines = new LinkedList<>();
    List<NetstatLine> netstatLinesToReturn = new LinkedList<>();

    @Override
    public void afterPropertiesSet() throws Exception {
        new Thread(() -> {
            try {
                List<NetstatLine> netstatLines = new LinkedList<>();
                netstatProcess = new ProcessBuilder().command("netstat", "-anop", "tcp", "10").start();
                BufferedReader reader = new BufferedReader(new InputStreamReader(netstatProcess.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    String trimmedLine = line.trim();
                    if (trimmedLine.isEmpty()) {
                        continue;
                    }
                    if (trimmedLine.equals("Active Connections")) {
                        final List<NetstatLine> finalNetstatLines = netstatLines;
                        // New batch
                        netstatLines = new LinkedList<>();
                        // Expect the processing to finish after 2 seconds;
                        Timer timer = new Timer();
                        timer.schedule(new TimerTask() {
                            @Override
                            public void run() {
                                netstatLinesToReturn = finalNetstatLines;
                            }
                        }, 2000);
                        continue;
                    }
                    String[] lineParts = trimmedLine.split("\\s+");
                    // must have 5 parts (Proto, Local Address, Foreign Address, State, PID/Program name)
                    if (lineParts.length != 5) {
                        continue;
                    }
                    // skip header line
                    if (lineParts[0].equals("Proto")) {
                        continue;
                    }
                    netstatLines.add(NetstatLine.parse(line));
                }
            } catch (IOException ignore) {
            }
        }).start();
    }

    @Override
    public void destroy() throws Exception {
        if (netstatProcess != null) {
            netstatProcess.destroy();
        }
    }

    public List<NetstatLine> getNetstatLines()  {
        return netstatLinesToReturn;
    }
}
