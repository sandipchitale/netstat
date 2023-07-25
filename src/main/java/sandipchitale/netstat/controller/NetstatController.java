package sandipchitale.netstat.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import sandipchitale.netstat.model.NetstatLine;
import sandipchitale.netstat.service.NetstatService;

import java.util.List;

@RestController
public class NetstatController {
    private final NetstatService netstatService;

    public NetstatController(NetstatService netstatService) {
        this.netstatService = netstatService;
    }

    @GetMapping("/")
    public int getNetstatLinesSize() {
        return netstatService.getNetstatLines().size();
    }

    @GetMapping("/netstat")
    public List<NetstatLine> getNetstatLines() {
        return netstatService.getNetstatLines();
    }
}
