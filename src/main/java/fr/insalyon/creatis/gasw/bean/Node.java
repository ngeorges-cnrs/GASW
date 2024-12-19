/* Copyright CNRS-CREATIS
 *
 * Rafael Silva
 * rafael.silva@creatis.insa-lyon.fr
 * http://www.rafaelsilva.com
 *
 * This software is a grid-enabled data-driven workflow manager and editor.
 *
 * This software is governed by the CeCILL  license under French law and
 * abiding by the rules of distribution of free software.  You can  use,
 * modify and/ or redistribute the software under the terms of the CeCILL
 * license as circulated by CEA, CNRS and INRIA at the following URL
 * "http://www.cecill.info".
 *
 * As a counterpart to the access to the source code and  rights to copy,
 * modify and redistribute granted by the license, users are provided only
 * with a limited warranty  and the software's author,  the holder of the
 * economic rights,  and the successive licensors  have only  limited
 * liability.
 *
 * In this respect, the user's attention is drawn to the risks associated
 * with loading,  using,  modifying and/or developing or reproducing the
 * software by the user in light of its specific status of free software,
 * that may mean  that it is complicated to manipulate,  and  that  also
 * therefore means  that it is reserved for developers  and  experienced
 * professionals having in-depth computer knowledge. Users are therefore
 * encouraged to load and test the software's suitability as regards their
 * requirements in conditions enabling the security of their systems and/or
 * data to be ensured and,  more generally, to use and operate it in the
 * same conditions as regards security.
 *
 * The fact that you are presently reading this means that you have had
 * knowledge of the CeCILL license and that you accept its terms.
 */
package fr.insalyon.creatis.gasw.bean;

import jakarta.persistence.*;

/**
 *
 * @author Rafael Silva
 */
@Entity
@NamedQueries({
    @NamedQuery(name = "Node.findBySiteAndNodeName", query = "FROM Node n WHERE n.nodeID.siteName = :siteName AND n.nodeID.nodeName = :nodeName")
})
@Table(name = "Nodes")
public class Node {

    private NodeID nodeID;
    private int nCpus;
    private String cpuModelName;
    private double cpuMhz;
    private int cpuCacheSize;
    private double cpuBogoMips;
    private int memTotal;

    public Node() {
    }

    public Node(NodeID nodeID, int nCpus, String cpuModelName, double cpuMhz,
            int cpuCacheSize, double cpuBogoMips, int memTotal) {

        this.nodeID = nodeID;
        this.nCpus = nCpus;
        this.cpuModelName = cpuModelName;
        this.cpuMhz = cpuMhz;
        this.cpuCacheSize = cpuCacheSize;
        this.cpuBogoMips = cpuBogoMips;
        this.memTotal = memTotal;
    }

    @EmbeddedId
    public NodeID getNodeID() {
        return nodeID;
    }

    @Column(name = "cpu_bogomips")
    public double getCpuBogoMips() {
        return cpuBogoMips;
    }

    @Column(name = "cpu_cache_size")
    public int getCpuCacheSize() {
        return cpuCacheSize;
    }

    @Column(name = "cpu_mhz")
    public double getCpuMhz() {
        return cpuMhz;
    }

    @Column(name = "cpu_model_name")
    public String getCpuModelName() {
        return cpuModelName;
    }

    @Column(name = "mem_total")
    public int getMemTotal() {
        return memTotal;
    }

    @Column(name = "ncpus")
    public int getnCpus() {
        return nCpus;
    }

    public void setNodeID(NodeID nodeID) {
        this.nodeID = nodeID;
    }

    public void setCpuBogoMips(double cpuBogoMips) {
        this.cpuBogoMips = cpuBogoMips;
    }

    public void setCpuCacheSize(int cpuCacheSize) {
        this.cpuCacheSize = cpuCacheSize;
    }

    public void setCpuMhz(double cpuMhz) {
        this.cpuMhz = cpuMhz;
    }

    public void setCpuModelName(String cpuModelName) {
        this.cpuModelName = cpuModelName;
    }

    public void setMemTotal(int memTotal) {
        this.memTotal = memTotal;
    }

    public void setnCpus(int nCpus) {
        this.nCpus = nCpus;
    }
}