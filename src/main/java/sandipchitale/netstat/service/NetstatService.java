package sandipchitale.netstat.service;

import org.springframework.stereotype.Service;
import sandipchitale.netstat.model.NetstatLine;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.LinkedList;
import java.util.List;

@Service
public class NetstatService {
    public List<NetstatLine> getNetstatLines()  {
        List<NetstatLine> netstatLines = new LinkedList<>();
        try {
            Process netstatProcess = new ProcessBuilder().command("netstat", "-anop", "tcp").start();
            try {
                BufferedReader reader = new BufferedReader(new InputStreamReader(netstatProcess.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    String[] lineParts = line.trim().split("\\s+");
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
            } finally {
                try {
                    netstatProcess.waitFor();
                } catch (InterruptedException ignore) {
                }
            }
        } catch (IOException ignore) {}
        return netstatLines;
    }
}
