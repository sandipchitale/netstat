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
                line = reader.readLine();
                line = reader.readLine();
                line = reader.readLine();
                line = reader.readLine();
                if (line != null) {
                    while ((line = reader.readLine()) != null) {
                        netstatLines.add(NetstatLine.parse(line));
                    }
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
