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
                netstatProcess = new ProcessBuilder().command("netstat", "-anop", "tcp", "5").start();
                BufferedReader reader = new BufferedReader(new InputStreamReader(netstatProcess.getInputStream()));
                final long[] start = new long[]{1};
                final long[] lastEntry =  new long[]{1};

                String line;
                while ((line = reader.readLine()) != null) {
                    String trimmedLine = line.trim();
                    if (trimmedLine.isEmpty()) {
                        continue;
                    }
                    if (trimmedLine.equals("Active Connections")) {
                        // New batch is starting
                        netstatLines = new LinkedList<>();
                        start[0] = System.currentTimeMillis();
                        // Save reference to the current batch
                        final List<NetstatLine> finalNetstatLines = netstatLines;
                        // Expect the processing to finish after 100 milliseconds
                        // so we start a timer for 100 milliseconds from now
                        // and then copy over the reference to
                        // the one that is to be returned
                        Timer timer = new Timer();
                        timer.schedule(new TimerTask() {
                            @Override
                            public void run() {
                                netstatLinesToReturn = new LinkedList<>(finalNetstatLines);
                            }
                        }, 100);
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
                    lastEntry[0] = System.currentTimeMillis();
                    netstatLines.add(NetstatLine.parse(lastEntry[0], line));
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
