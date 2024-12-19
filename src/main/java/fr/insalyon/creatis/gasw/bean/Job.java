/* Copyright CNRS-CREATIS
 *
 * Rafael Ferreira da Silva
 * rafael.silva@creatis.insa-lyon.fr
 * http://www.rafaelsilva.com
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

import fr.insalyon.creatis.gasw.execution.GaswStatus;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import jakarta.persistence.*;
import org.hibernate.annotations.Index;

/**
 *
 * @author Rafael Ferreira da Silva
 */
@Entity
@NamedQueries({
    @NamedQuery(name = "Job.findById", query = "FROM Job j WHERE j.id = :id"),
    @NamedQuery(name = "Job.findByStatus", query = "FROM Job j WHERE j.status = :status"),
    @NamedQuery(name = "Job.findByParameters", query = "FROM Job j WHERE j.parameters = :parameters"),
    @NamedQuery(name = "Job.findActiveByInvocationID", query = "FROM Job j WHERE j.invocationID = :invocationID AND (status = :submitted OR status = :queued OR status = :running OR status = :kill OR status = :replicate OR status = :reschedule)"),
    @NamedQuery(name = "Job.findFailedByInvocationID", query = "FROM Job j WHERE j.invocationID = :invocationID AND (status = :error OR status = :stalled OR status = :error_held OR status = :stalled_held)"),
    @NamedQuery(name = "Job.getActive", query = "FROM Job j WHERE status = :submitted OR status = :queued OR status = :running OR status = :kill OR status = :replicate OR status = :reschedule"),
    @NamedQuery(name = "Job.getCompletedJobsByInvocationID", query = "SELECT COUNT(j.id) FROM Job j WHERE j.invocationID = :invocationID AND status = :completed"),
    @NamedQuery(name = "Job.getRunningByCommand", query = "FROM Job j WHERE j.command = :command AND (status = :running OR status = :kill OR status = :replicate OR status = :reschedule)"),
    @NamedQuery(name = "Job.getCompletedByCommand", query = "FROM Job j WHERE j.command = :command AND (status = :completed)"),
    @NamedQuery(name = "Job.getFailedByCommand", query = "FROM Job j WHERE j.command = :command AND (status = :error OR status = :stalled OR status = :error_held OR status = :stalled_held)"),
    @NamedQuery(name = "Job.getJobsByCommand", query = "FROM Job j WHERE j.command = :command"),
    @NamedQuery(name = "Job.getInvocationsByCommand", query = "SELECT DISTINCT j.invocationID FROM Job j WHERE j.command = :command")
            })
@Table(name = "Jobs")
public class Job {

    private String id;
    private String simulationID;
    private GaswStatus status;
    private boolean isReplicating;
    private boolean isBeingKilled;
    private int exitCode;
    private String exitMessage;
    private Date creation;
    private Date queued;
    private Date download;
    private Date running;
    private Date upload;
    private Date end;
    private int checkpointInit;
    private int checkpointUpload;
    private Node node;
    private String command;
    private String fileName;
    private String parameters;
    private String executor;
    private List<Data> data;
    private int invocationID;
    private String diracSite;

    public Job() {
    }

    /**
     *
     * @param id
     * @param simulationID
     * @param status
     * @param command
     * @param fileName
     * @param parameters
     * @param executor
     */
    public Job(String id, String simulationID, GaswStatus status, String command,
            String fileName, String parameters, String executor) {

        this(id, simulationID, status, -1, "", null, null, null, null, null,
                null, null, command, fileName, parameters, executor, 
                new ArrayList<Data>(), -1,null);
    }

    /**
     *
     * @param id
     * @param simulationID
     * @param status
     * @param exitCode
     * @param exitMessage
     * @param creation
     * @param queued
     * @param download
     * @param running
     * @param upload
     * @param end
     * @param node
     * @param command
     * @param fileName
     * @param parameters
     * @param executor
     * @param data
     * @param invocationID
     * @param diracSite
     */
    public Job(String id, String simulationID, GaswStatus status, int exitCode,
            String exitMessage, Date creation, Date queued, Date download,
            Date running, Date upload, Date end, Node node, String command,
            String fileName, String parameters, String executor, List<Data> data,
            int invocationID, String diracSite) {

        this.id = id;
        this.simulationID = simulationID;
        this.status = status;
        this.exitCode = exitCode;
        this.exitMessage = exitMessage;
        this.creation = creation;
        this.queued = queued;
        this.download = download;
        this.running = running;
        this.upload = upload;
        this.end = end;
        this.node = node;
        this.command = command;
        this.fileName = fileName;
        this.parameters = parameters;
        this.executor = executor;
        this.data = data;
        this.invocationID = invocationID;
        this.isReplicating = false;
        this.isBeingKilled = false;
        this.diracSite = diracSite;
    }

    @Id
    @Column(name = "id")
    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    @Column(name = "simulation_id")
    public String getSimulationID() {
        return simulationID;
    }

    public void setSimulationID(String simulationID) {
        this.simulationID = simulationID;
    }

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "creation")
    public Date getCreation() {
        return creation;
    }

    public void setCreation(Date creation) {
        this.creation = creation;
    }

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "download")
    public Date getDownload() {
        return download;
    }

    public void setDownload(Date download) {
        this.download = download;
    }

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "end_e")
    public Date getEnd() {
        return end;
    }

    public void setEnd(Date end) {
        this.end = end;
    }

    @Column(name = "exit_code")
    public int getExitCode() {
        return exitCode;
    }

    public void setExitCode(int exitCode) {
        this.exitCode = exitCode;
    }

    @Column(name = "exit_message")
    public String getExitMessage() {
        return exitMessage;
    }

    public void setExitMessage(String exitMessage) {
        this.exitMessage = exitMessage;
    }

    @ManyToOne
    @JoinColumns({
        @JoinColumn(name = "node_site", referencedColumnName = "site"),
        @JoinColumn(name = "node_name", referencedColumnName = "node_name")
    })
    public Node getNode() {
        return node;
    }

    public void setNode(Node node) {
        this.node = node;
    }

    @Column(name = "dirac_site")
    public String getDiracSite() {
        return diracSite;
    }

    public void setDiracSite(String diracSite) {
        this.diracSite = diracSite;
    }

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "queued")
    public Date getQueued() {
        return queued;
    }

    public void setQueued(Date queued) {
        this.queued = queued;
    }

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "running")
    public Date getRunning() {
        return running;
    }

    public void setRunning(Date running) {
        this.running = running;
    }

    @Column(name = "status")
    @Enumerated(value = EnumType.STRING)
    public GaswStatus getStatus() {
        return status;
    }

    public void setStatus(GaswStatus status) {
        this.status = status;
    }

    @Column(name = "isReplicating")
    public boolean isReplicating() {
        return isReplicating;
    }

    public void setReplicating(boolean replicating) {
        isReplicating = replicating;
    }

    @Column(name = "isBeingKilled")
    public boolean isBeingKilled() {
        return isBeingKilled;
    }

    public void setBeingKilled(boolean isBeingKilled) {
        this.isBeingKilled = isBeingKilled;
    }

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "upload")
    public Date getUpload() {
        return upload;
    }

    public void setUpload(Date upload) {
        this.upload = upload;
    }

    @Column(name = "command")
    public String getCommand() {
        return command;
    }

    @Column(name = "file_name")
    public String getFileName() {
        return fileName;
    }

    public void setFileName(String fileName) {
        this.fileName = fileName;
    }

    @Column(name = "parameters", length = 10000)
    @Index(name = "paramIndex")
    public String getParameters() {
        return parameters;
    }

    @Column(name = "checkpoint_init")
    public int getCheckpointInit() {
        return checkpointInit;
    }

    public void setCheckpointInit(int checkpointInit) {
        this.checkpointInit = checkpointInit;
    }

    @Column(name = "checkpoint_upload")
    public int getCheckpointUpload() {
        return checkpointUpload;
    }

    public void setCheckpointUpload(int checkpointUpload) {
        this.checkpointUpload = checkpointUpload;
    }

    public void setCommand(String command) {
        this.command = command;
    }

    public void setParameters(String parameters) {
        this.parameters = parameters;
    }

    @Column(name = "executor")
    public String getExecutor() {
        return executor;
    }

    public void setExecutor(String executor) {
        this.executor = executor;
    }

    @ManyToMany(cascade = CascadeType.ALL)
    @JoinTable(name = "job_data",
            joinColumns = {
        @JoinColumn(name = "id")},
            inverseJoinColumns = {
        @JoinColumn(name = "data_path")})
    public List<Data> getData() {
        return data;
    }

    public void setData(List<Data> data) {
        this.data = data;
    }

    @Column(name = "invocation_id")
    @Index(name = "invocationIndex")
    public int getInvocationID() {
        return invocationID;
    }

    public void setInvocationID(int invocationID) {
        this.invocationID = invocationID;
    }
}
